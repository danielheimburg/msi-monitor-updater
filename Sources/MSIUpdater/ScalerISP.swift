import Foundation

/// A500/A300 primitives for an already selected internal I²C or UART interface. The owner must
/// serialize complete operations and close the session on any failure. Reads alter
/// volatile sequencer state. Programming methods mutate protection or flash and
/// require durable intent plus a freshly verified plan from the caller.
/// Wire framing and sequencing are documented in docs/msi/update-sequence.md.
/// Initialize, then read JEDEC
/// before other sequencer reads. Bank selection requires a separate EAR check.
struct ScalerHardware: Codable, Sendable {
    let scalerID: UInt16
    let flashID: [UInt8]

    var capacity: Int { 1 << Int(flashID.last ?? 0) }
    var sectorMilliseconds: UInt64 {
        if flashID.first == 0xEF { return 400 }
        return switch flashID.last { case 0x17: 800; case 0x18: 500; default: 450 }
    }

    func validate() throws {
        guard [UInt16(0xA500), 0xA300].contains(scalerID),
              flashID.count == 3,
              [UInt8(0xC8), 0xEF].contains(flashID[0]), flashID[1] == 0x40,
              (0x17...0x19).contains(flashID[2]) else {
            throw UpdaterError("The scaler or SPI flash does not have a reviewed programming contract.")
        }
    }
}

struct ScalerISP: Sendable {
    let session: HIDSession
    let hardware: ScalerHardware
    let transport: ScalerTransport

    static func connect(session: HIDSession, transport: ScalerTransport) async throws -> Self {
        // This provisional identity permits only the identification sequence.
        let probe = Self(session: session, hardware: ScalerHardware(scalerID: 0xA500, flashID: [0xC8, 0x40, 0x19]), transport: transport)
        let chip = try await probe.initializeForIdentification()
        let flash = try await probe.readJEDEC()
        let hardware = ScalerHardware(scalerID: chip, flashID: flash)
        try hardware.validate()
        return Self(session: session, hardware: hardware, transport: transport)
    }

    func identifyScaler() async throws -> UInt16 {
        let request: [UInt8] = transport == .uart
            ? [0xA0, 0, 0] + Array("#nvtISP_MODE_ON#$$".utf8)
            : [0xA0, 0x6F, 0, 4, 0x34, 6, 0x36]
        let reply = try await exchange(request)
        guard (transport == .uart || (reply[4] == 0x6F && reply[5] == 2)),
              [UInt8(0xA5), 0xA3].contains(reply[6]), reply[7] == 0,
              Self.xor(reply[4...7]) == reply[8] else {
            throw UpdaterError("The ISP controller is outside the reviewed nine-descriptor A500/A300 family.")
        }
        return UInt16(reply[6]) << 8 | UInt16(reply[7])
    }

    /// A500/A300 pre-ID path in docs/msi/update-sequence.md; no protection setup.
    func initializeForIdentification() async throws -> UInt16 {
        let chip = try await identifyScaler()
        if transport == .i2c {
            try await writeRegister(0xF0E0, 0xAA)
            try await writeRegister(0xF0E2, 0xAA)
            let mode = try await readRegister(0xF049) & 0x0F
            guard mode <= 7 else { throw UpdaterError("Unsupported scaler initialization mode.") }
            try await writeRegister(0xF055, mode)
        }
        for selector: UInt8 in [2, 0x12] {
            let packets: [[UInt8]] = [
                [0xBC, 0, 0, 0xB0, 0xFF, 0x3D],
                [0xBE, 0, 0, 0xB0, 0x80, 8, 0, selector, 0x9F, 0, 0x10, 0, 0],
                [0xBC, 0, 0, 0xB0, 0x8C, 0x80]
            ]
            for packet in packets {
                try await simpleAcknowledgement(packet, delay: 1)
            }
        }
        let registers: [(UInt16, UInt8)] = [
            (0xF1DF, 0x80), (0xF1A8, 2), (0xF0E0, 0xAA), (0xF0E2, 0xAA),
            (0xF068, 0x9F), (0xF067, 0x20), (0xF0E5, 0x40), (0xF0E5, 0),
            (0xF0E6, 4), (0xF04E, 0), (0xD909, 0x55), (0xD90A, 0x55),
            (0xD906, 4), (0xD905, 3), (0xD904, 0xFE), (0xD90B, 0x84),
            (0xD90C, 0x30), (0xF04C, 0x60), (0xD929, 6)
        ]
        for (address, value) in registers { try await writeRegister(address, value) }
        try await pause(500)
        return chip
    }

    func readJEDEC() async throws -> [UInt8] {
        // Initial JEDEC writes F0C0; subsequent reads preserve its value.
        try await writeRegister(0xF0C0, 0x13)
        try await configureSequence([0x9F], count: 3)
        try await executeSequence()
        var scratch: [UInt8] = []
        for offset in 0..<16 { scratch.append(try await readRegister(0xA700 + UInt16(offset))) }
        return Array(scratch[3...5])
    }

    enum StatusRegister: UInt8, Sendable {
        case extendedAddress = 0xC8
    }

    func readStatus(_ register: StatusRegister) async throws -> UInt8 {
        try await readSequence([register.rawValue], count: 1)[0]
    }

    /// Uses four-byte opcode0C for 32MiB, otherwise 24-bit opcode0B.
    /// Calls are bounded to64KiB; the owner decides which physical ranges to acquire.
    func readPhysical(address: UInt32, count: Int) async throws -> [UInt8] {
        guard count > 0, count <= 65_536,
              UInt64(address) + UInt64(count) <= UInt64(hardware.capacity) else {
            throw UpdaterError("Physical read exceeds the identified flash capacity.")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        while bytes.count < count {
            let current = address + UInt32(bytes.count)
            // Keep completed chunks; each explicit-address chunk is independent.
            let chunk = min(64, count - bytes.count)
            let command = hardware.capacity == 0x2000000
                ? [UInt8(0x0C), UInt8(current >> 24)] + Self.address24(current) + [0]
                : [UInt8(0x0B)] + Self.address24(current) + [0]
            do {
                bytes += try await readSequence(command, count: chunk)
            } catch is HIDResponseTimeout where transport == .i2c {
                // One host-only reopen per failed chunk. A second failure of
                // this chunk propagates. Never replay program/erase, protection,
                // bank selection or a completion/checksum transaction.
                try await session.reopenAfterReplyTimeout()
                guard transport == .i2c, try await identifyScaler() == hardware.scalerID,
                      try await readJEDEC() == hardware.flashID else {
                    throw UpdaterError("Flash identity changed after read-channel reopen.")
                }
                bytes += try await readSequence(command, count: chunk)
            }
        }
        return bytes
    }

    /// A2 changes selected bank; its acknowledgement does not echo/prove the bank.
    func selectBank(_ bank: UInt8) async throws {
        guard bank <= (hardware.capacity > 0x1000000 ? 1 : 0) else { throw UpdaterError("Only flash banks0 and1 are supported.") }
        let reply = try await command(0xA2, body: [0x6E, 2, 0x0F, bank])
        guard reply[6] == 0xF0, Self.xor(reply[4...7]) == reply[8] else {
            throw UpdaterError("Invalid ISP bank-selection acknowledgement.")
        }
    }

    /// Sum16 over512 bytes in the currently selected bank, not a physical address.
    func pageChecksum(address: UInt32) async throws -> UInt16 {
        guard address < 0x1000000, address % 512 == 0 else {
            throw UpdaterError("Checksum requires an aligned bank-relative page address.") }
        let reply = try await command(0xB5, body: [0x6E, 4, 0x36] + Self.address24(address), delay: 10)
        guard (transport == .uart || (reply[4] == 0x6F && reply[5] == 3)), reply[6] == 0xC9,
              Self.xor(reply[4...8]) == reply[9] else {
            throw UpdaterError("Invalid flash-page checksum response.")
        }
        return UInt16(reply[7]) << 8 | UInt16(reply[8])
    }

    /// Reproduces the captured descriptor4E continuation. The owner must record
    /// mutation intent first. Any failure leaves protection state uncertain.
    func initializeProgramming() async throws {
        guard try await readJEDEC() == hardware.flashID else {
            throw UpdaterError("The flash identity changed before programming.")
        }
        try await writeRegister(0xF067, 0x20)
        if transport == .i2c {
            try await simpleAcknowledgement([0xAD, 0, 0, 0x6E, 2, 0x99, 0, 0xF5], delay: 10)
        } else {
            let reply = try await command(0xAD, body: [0x6E, 2, 0x99, 0], delay: 10)
            guard reply[6] == 0x66, Self.xor(reply[4...6]) == reply[7] else {
                throw UpdaterError("Invalid UART programming-control acknowledgement.")
            }
        }
        // Vendor index4E default: empty sequencer, with all three pointers atA700.
        _ = try await readRegister(0xF0C0)
        let emptyPointers: [(UInt16, UInt8)] = [
            (0xF0C1, 0xA7), (0xF0C2, 0), (0xF0C3, 0xA7),
            (0xF0C4, 0), (0xF0C5, 0xA7), (0xF0C6, 0)
        ]
        for (address, value) in emptyPointers { try await writeRegister(address, value) }
        try await executeSequence()
        for offset in 0..<16 { _ = try await readRegister(0xA700 + UInt16(offset)) }
        let first = try await readCommandStatus(0x05)
        let secondOpcode: UInt8 = 0x35
        let second = try await readCommandStatus(secondOpcode)
        let supportedSecondStatus: Bool
        supportedSecondStatus = hardware.flashID[0] == 0xC8 ? second & 0xFD == 0 : second & 0xC1 == 0
        guard first & 1 == 0, supportedSecondStatus else {
            throw UpdaterError("The flash is busy or has unreviewed status/security bits; stop before protection writes.")
        }
        if hardware.flashID[0] == 0xEF || hardware.capacity == 0x2000000 {
            let third = try await readCommandStatus(0x15)
            // WPS selects individual locks; ADS/ADP change the ordinary address
            // width on 32MiB parts, where programming depends on 24-bit + EAR.
            // GigaDevice instead stores power-up ADP in SR3 bit4.
            let unsupportedMask: UInt8 = hardware.flashID[0] == 0xC8 ? 0x10 : (hardware.capacity == 0x2000000 ? 7 : 4)
            guard third & unsupportedMask == 0 else {
                throw UpdaterError("Flash lock/address mode is unsupported; stop without changing it.")
            }
        }
        let protectionRegisters: [(UInt16, UInt8, Bool)] = [
            (0xF134, 0x40, true), (0xF11D, 0x40, false), (0xF11C, 0x40, true)
        ]
        for (address, mask, set) in protectionRegisters {
            let previous = try await readRegister(address)
            try await writeRegister(address, set ? previous | mask : previous & ~mask)
        }
        let requestedFirst: UInt8
        let expectedSecond: UInt8
        requestedFirst = first & (hardware.capacity == 0x2000000 ? 0x43 : 0x63)
        expectedSecond = hardware.flashID[0] == 0xEF ? second | 2 : 2
        let padding = Array(repeating: UInt8(hardware.flashID[0] == 0xC8 && hardware.capacity == 0x2000000 ? 0xCC : 0), count: 6)
        try await spiCommand([6] + padding, writeCount: 1, readCount: 0)
        if hardware.flashID[0] == 0xC8 && hardware.capacity < 0x2000000 {
            try await spiCommand([1, requestedFirst] + Array(padding.prefix(5)), writeCount: 2, readCount: 0)
            try await spiCommand([6] + padding, writeCount: 1, readCount: 0)
            try await spiCommand([0x31, expectedSecond] + Array(padding.prefix(5)), writeCount: 2, readCount: 0)
        } else {
            try await spiCommand([1, requestedFirst, expectedSecond] + Array(padding.prefix(4)), writeCount: 3, readCount: 0)
        }
        try await pause(hardware.sectorMilliseconds)
        let resultingFirst = try await readCommandStatus(0x05)
        let resultingSecond = try await readCommandStatus(secondOpcode)
        // WIP/WEL are read-only and clear after a completed status write.
        guard resultingFirst == requestedFirst & 0xFC, resultingSecond == expectedSecond,
              resultingFirst & 0x9C == 0 else {
            throw UpdaterError("Flash protection readback differs from the planned state; stop without retry or reset.")
        }
    }

    /// Programs exactly one bank-relative4KiB block. Caller owns bank selection,
    /// destination authorization and journal durability. Never retry a failed call.
    func programBlock(address: UInt32, bytes: [UInt8]) async throws {
        guard address < 0x1000000, address % 4096 == 0, bytes.count == 4096 else {
            throw UpdaterError("Programming requires one aligned bank-relative4KiB block.")
        }
        if transport == .uart {
            try await eraseSector(address: address)
            for offset in stride(from: 0, to: bytes.count, by: 512) {
                try await programPage(address: address + UInt32(offset), bytes: Array(bytes[offset..<(offset + 512)]))
            }
            return
        }
        try await writeMailbox(0xFF, 0xF2)
        try await simpleAcknowledgement([0xBD, 0, 0, 0xB0, 0] + Self.address24(address) + [0x10, 0, 0], delay: 1)
        try await writeMailbox(0xFF, 0xF3)
        try await writeMailbox(0xE2, 0x87)
        try await writeMailbox(0xFF, 0xD0)
        try await sendFragment([0xBF, 0, 0, 0xB0, 0] + Array(bytes[0..<58]))
        for offset in stride(from: 58, to: 4078, by: 60) {
            try await sendFragment([0xC0, 0, 0] + Array(bytes[offset..<(offset + 60)]))
        }
        try await simpleAcknowledgement([0xC1, 0, 0] + Array(bytes[4078..<4096]), delay: 1)
        let commit: [UInt8] = [0x6E, 7, 0xB5, 0xF0, 0x0F, 0x6E, 0x91, 0x13, 0xEC]
        try await simpleAcknowledgement([0xC2, 0, 0] + commit + [Self.xor(commit)], delay: 1)
        try await pause(200)
        try await writeMailbox(0xFF, 0xF2)
        let deadline = ContinuousClock.now + .seconds(15)
        var completed = false
        // Descriptor4E: (450 +96)/2 iterations; successful polls also settle20ms.
        for _ in 0..<((hardware.sectorMilliseconds + 96) / 2) {
            guard ContinuousClock.now < deadline else { break }
            let reply = try await exchange([0xC3, 0xB1, 0, 0xB0, 5], delay: 1)
            guard reply[2] == 1, reply[3] == 0, reply[4] == 0xB1,
                  reply[6...].allSatisfy({ $0 == 0 }) else {
                throw UpdaterError("Invalid block-completion response; commit outcome is uncertain.")
            }
            try await pause(20)
            if reply[5] == 0x55 { completed = true; break }
            if reply[5] == 5 { throw UpdaterError("Monitor reported block programming failure; do not retry.") }
            try await pause(20)
        }
        guard completed else { throw UpdaterError("Block programming deadline expired; commit outcome is uncertain.") }
        for offset in stride(from: 0, to: 4096, by: 512) {
            let expected = bytes[offset..<(offset + 512)].reduce(UInt16(0)) { $0 &+ UInt16($1) }
            guard try await pageChecksum(address: address + UInt32(offset)) == expected else {
                throw UpdaterError("Programmed block page checksum differs; stop without retry.")
            }
        }
    }

    /// UART page programming requires a separate, non-retriable 4KiB erase.
    /// This is one sector from the vendor's B2 range command; never batch across
    /// a preserved metadata or boot range. The plan owns destination selection.
    private func eraseSector(address: UInt32) async throws {
        guard transport == .uart, address % 4096 == 0, address < 0x1000000 else {
            throw UpdaterError("Invalid UART sector erase range.")
        }
        let sector = address / 4096
        let body: [UInt8] = [0x6E, 0x0A, 0x2D, 0xAA, 0x55, 0xCC, 0x33, 0xE2, 0x1D,
            UInt8(sector >> 8), UInt8(sector & 255), 0]
        let reply = try await command(0xB2, body: body, delay: hardware.sectorMilliseconds)
        guard reply[6] == 0xD2, Self.xor(reply[4...6]) == reply[7] else {
            throw UpdaterError("Invalid UART sector-erase acknowledgement; outcome is uncertain.")
        }
    }

    /// Programs one512-byte bank-relative page, including metadata invalidation.
    /// B8 completes mutation; a lost reply must never trigger automatic replay.
    func programPage(address: UInt32, bytes: [UInt8]) async throws {
        guard address < 0x1000000, address % 512 == 0, bytes.count == 512 else {
            throw UpdaterError("Programming requires one aligned bank-relative512-byte page.")
        }
        let header: [UInt8] = [0x6E, 0, 0x3C] + Self.address24(address) + [0xF0, 0x0F, 0x6E, 0x91, 0x13, 0xEC]
        var checksum = Self.xor(header + Array(bytes[0..<48]))
        try await sendFragment([0xB6, 0, 0] + header + Array(bytes[0..<48]))
        for offset in stride(from: 48, to: 468, by: 60) {
            let fragment = Array(bytes[offset..<(offset + 60)])
            checksum ^= Self.xor(fragment)
            try await sendFragment([0xB7, 0, 0] + fragment)
        }
        let tail = Array(bytes[468..<512])
        checksum ^= Self.xor(tail)
        let reply = try await exchange([0xB8, transport == .i2c ? 0x6F : 0, 0] + tail + [checksum], delay: 10)
        guard reply[6] == 0xC3, Self.xor(reply[4...6]) == reply[7] else {
            throw UpdaterError("Invalid page-program acknowledgement; outcome is uncertain.")
        }
        let expected = bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        guard try await pageChecksum(address: address) == expected else {
            throw UpdaterError("Programmed page checksum differs; stop without retry.")
        }
    }

    private func readCommandStatus(_ opcode: UInt8) async throws -> UInt8 {
        try await spiCommand([opcode] + Array(repeating: 0, count: 6), writeCount: 1, readCount: 1)
        try await pause(100)
        return try await readRegister(0xF880)
    }

    private func spiCommand(_ bytes: [UInt8], writeCount: UInt8, readCount: UInt8) async throws {
        let body: [UInt8] = [0x6E, 9, 0x53] + bytes + [(readCount << 4) | writeCount]
        let reply = try await command(0xAE, body: body, delay: 20)
        guard reply[6] == 0xAC, Self.xor(reply[4...6]) == reply[7] else {
            throw UpdaterError("Invalid flash-command acknowledgement; outcome is uncertain.")
        }
    }

    private func writeMailbox(_ address: UInt8, _ value: UInt8) async throws {
        // BC acknowledgements do not echo the address or value. Reopening and
        // replaying could let a late ACK satisfy a different mailbox write.
        try await simpleAcknowledgement([0xBC, 0, 0, 0xB0, address, value], delay: 1)
    }

    private func simpleAcknowledgement(_ payload: [UInt8], delay: UInt64) async throws {
        if transport == .uart {
            _ = try await session.exchange(MonitorProtocol.report(transport.reportID, payload), expectsReply: false)
            try await pause(delay)
            return
        }
        let reply = try await exchange(payload, delay: delay)
        guard reply == (try MonitorProtocol.report(transport.reportID, [payload[0], 1])) else {
            throw UpdaterError("Invalid programming/setup acknowledgement; stop without retry.")
        }
    }

    private func sendFragment(_ payload: [UInt8]) async throws {
        _ = try await session.exchange(MonitorProtocol.report(transport.reportID, payload), expectsReply: false)
    }

    private func readSequence(_ spi: [UInt8], count: Int) async throws -> [UInt8] {
        _ = try await readRegister(0xF0C0)
        try await configureSequence(spi, count: count)
        try await executeSequence()
        var result: [UInt8] = []
        for offset in 0..<count {
            result.append(try await readRegister(0xA702 + UInt16(spi.count + offset)))
        }
        return result
    }

    private func configureSequence(_ spi: [UInt8], count: Int) async throws {
        guard (1...6).contains(spi.count), (1...168).contains(count) else {
            throw UpdaterError("Invalid bounded ISP read sequence.") }
        let body = [UInt8(spi.count), UInt8(count)] + spi
        let pointers: [(UInt16, UInt8)] = [
            (0xF0C1, 0xA7), (0xF0C2, 0), (0xF0C3, 0xA7),
            (0xF0C4, 2), (0xF0C5, 0xA7), (0xF0C6, UInt8(body.count))
        ]
        for (address, value) in pointers { try await writeRegister(address, value) }
        for (offset, value) in body.enumerated() { try await writeRegister(0xA700 + UInt16(offset), value) }
    }

    private func executeSequence() async throws {
        let reply = try await command(0xAF, body: [0x6E, 1, 0x25], delay: 100)
        guard reply[6] == 0xDA, Self.xor(reply[4...6]) == reply[7] else {
            throw UpdaterError("Invalid ISP sequencer acknowledgement.") }
        try await pause(200)
    }

    private func readRegister(_ address: UInt16) async throws -> UInt8 {
        let reply = try await command(0xAA, body: [0x6E, 3, 0x87, UInt8(address >> 8), UInt8(address & 255)], delay: 5)
        guard reply[6] == 0x78, Self.xor(reply[4...7]) == reply[8] else {
            throw UpdaterError("Invalid ISP register-read response.") }
        return reply[7]
    }

    private func writeRegister(_ address: UInt16, _ value: UInt8) async throws {
        let reply = try await command(0xA9, body: [0x6E, 4, 0x78, UInt8(address >> 8), UInt8(address & 255), value], delay: 5)
        guard reply[6] == 0x87, Self.xor(reply[4...6]) == reply[7] else {
            throw UpdaterError("Invalid ISP register-write acknowledgement.") }
    }

    private func command(_ opcode: UInt8, body: [UInt8], delay: UInt64 = 0) async throws -> [UInt8] {
        try await exchange([opcode, transport == .i2c ? 0x6F : 0, 0] + body + [Self.xor(body)], delay: delay)
    }

    private func exchange(_ payload: [UInt8], delay: UInt64 = 0) async throws -> [UInt8] {
        let reply = try await session.exchange(MonitorProtocol.report(transport.reportID, payload))
        guard reply.count == 64, reply[0] == transport.reportID, reply[1] == payload[0], (transport == .uart || reply[2] != 0) else {
            throw UpdaterError("Unexpected ISP response; stop this session.") }
        // Async HID reception remains active. Retain at least the vendor's delay
        // before any dependent command, even when a reply arrives immediately.
        if delay > 0 { try await pause(delay) }
        return reply
    }

    private static func address24(_ address: UInt32) -> [UInt8] {
        [UInt8((address >> 16) & 255), UInt8((address >> 8) & 255), UInt8(address & 255)]
    }

    private static func xor<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }

    private func pause(_ milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

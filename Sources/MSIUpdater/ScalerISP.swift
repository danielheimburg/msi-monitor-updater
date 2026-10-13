import Foundation

/// A500 read and programming primitives for an already selected ISP interface. The owner must
/// serialize complete operations and close the session on any failure. Reads alter
/// volatile sequencer state. Programming methods mutate protection or flash and
/// require durable intent plus a freshly verified plan from the caller.
/// Wire framing and sequencing are documented in docs/msi/update-sequence.md.
/// Initialize, then read JEDEC
/// before other sequencer reads. Bank selection requires a separate EAR check.
struct ScalerISP: Sendable {
    let session: HIDSession

    func identifyA500() async throws {
        let reply = try await exchange([0xA0, 0x6F, 0, 4, 0x34, 6, 0x36])
        guard reply[4] == 0x6F, reply[5] == 2,
              reply[6] == 0xA5, reply[7] == 0,
              Self.xor(reply[4...7]) == reply[8] else {
            throw UpdaterError("The ISP controller is not the supported A500.")
        }
    }

    /// Exact A500 pre-ID path from entry-exit.md; no post-ID protection setup.
    func initializeForIdentification() async throws {
        try await identifyA500()
        try await writeRegister(0xF0E0, 0xAA)
        try await writeRegister(0xF0E2, 0xAA)
        let mode = try await readRegister(0xF049) & 0x0F
        guard mode <= 7 else { throw UpdaterError("Unsupported A500 initialization mode.") }
        try await writeRegister(0xF055, mode)
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
        case first = 0x05, second = 0x35, third = 0x15, extendedAddress = 0xC8
    }

    func readStatus(_ register: StatusRegister) async throws -> UInt8 {
        try await readSequence([register.rawValue], count: 1)[0]
    }

    func readSFDP(address: UInt32, count: Int) async throws -> [UInt8] {
        guard count > 0, count <= 168, address < 0x1000000,
              UInt64(address) + UInt64(count) <= 0x1000000 else {
            throw UpdaterError("SFDP read exceeds the bounded 24-bit range.")
        }
        return try await readSequence([0x5A] + Self.address24(address) + [0], count: count)
    }

    /// Uses explicit four-byte opcode0C, independent of the current EAR bank.
    /// Calls are bounded to64KiB; the owner decides which physical ranges to acquire.
    func readPhysical(address: UInt32, count: Int) async throws -> [UInt8] {
        guard count > 0, count <= 65_536,
              UInt64(address) + UInt64(count) <= 0x2000000 else {
            throw UpdaterError("Physical read exceeds the supported 32MiB flash.")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        while bytes.count < count {
            let current = address + UInt32(bytes.count)
            // Keep completed chunks; each explicit-address chunk is independent.
            let chunk = min(64, count - bytes.count)
            let command = [UInt8(0x0C), UInt8(current >> 24)] + Self.address24(current) + [0]
            do {
                bytes += try await readSequence(command, count: chunk)
            } catch is HIDResponseTimeout {
                // One host-only reopen per failed chunk. A second failure of
                // this chunk propagates. Never replay program/erase, protection,
                // bank selection or a completion/checksum transaction.
                try await session.reopenAfterReplyTimeout()
                try await identifyA500()
                guard try await readJEDEC() == [0xC8, 0x40, 0x19] else {
                    throw UpdaterError("Flash identity changed after read-channel reopen.")
                }
                bytes += try await readSequence(command, count: chunk)
            }
        }
        return bytes
    }

    /// A2 changes selected bank; its acknowledgement does not echo/prove the bank.
    func selectBank(_ bank: UInt8) async throws {
        guard bank <= 1 else { throw UpdaterError("Only flash banks0 and1 are supported.") }
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
        guard reply[4] == 0x6F, reply[5] == 3, reply[6] == 0xC9,
              Self.xor(reply[4...8]) == reply[9] else {
            throw UpdaterError("Invalid flash-page checksum response.")
        }
        return UInt16(reply[7]) << 8 | UInt16(reply[8])
    }

    /// Reproduces the captured descriptor4E continuation. The owner must record
    /// mutation intent first. Any failure leaves protection state uncertain.
    func initializeCapturedProgramming() async throws {
        guard try await readJEDEC() == [0xC8, 0x40, 0x19] else {
            throw UpdaterError("Programming requires the captured C84019 flash identity.")
        }
        try await writeRegister(0xF067, 0x20)
        try await simpleAcknowledgement([0xAD, 0, 0, 0x6E, 2, 0x99, 0, 0xF5], delay: 10)
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
        let second = try await readCommandStatus(0x35)
        guard [UInt8(0xC2), 0x40].contains(first), second == 2 else {
            throw UpdaterError("Flash protection differs from the captured C2/02 or completed40/02 state.")
        }
        let protectionRegisters: [(UInt16, UInt8, Bool)] = [
            (0xF134, 0x40, true), (0xF11D, 0x40, false), (0xF11C, 0x40, true)
        ]
        for (address, mask, set) in protectionRegisters {
            let previous = try await readRegister(address)
            try await writeRegister(address, set ? previous | mask : previous & ~mask)
        }
        // Preserve the captured seven-byte host buffers, including counted-out CC.
        try await spiCommand([6] + Array(repeating: 0xCC, count: 6), writeCount: 1, readCount: 0)
        try await spiCommand([1, first & 0x43, 2] + Array(repeating: 0xCC, count: 4), writeCount: 3, readCount: 0)
        try await pause(450)
        let resultingFirst = try await readCommandStatus(0x05)
        let resultingSecond = try await readCommandStatus(0x35)
        guard resultingFirst == 0x40, resultingSecond == 2 else {
            throw UpdaterError("Protection write did not reach captured40/02; stop without retry or reset.")
        }
    }

    /// Programs exactly one bank-relative4KiB block. Caller owns bank selection,
    /// destination authorization and journal durability. Never retry a failed call.
    func programBlock(address: UInt32, bytes: [UInt8]) async throws {
        guard address < 0x1000000, address % 4096 == 0, bytes.count == 4096 else {
            throw UpdaterError("Programming requires one aligned bank-relative4KiB block.")
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
        for _ in 0..<273 {
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
        let reply = try await exchange([0xB8, 0x6F, 0] + tail + [checksum], delay: 10)
        guard reply == (try MonitorProtocol.report(4, [0xB8, 1, 0, 0x6F, 1, 0xC3, 0xAD])) else {
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
        guard reply == (try MonitorProtocol.report(4, [0xAE, 1, 0, 0x6F, 1, 0xAC, 0xC2])) else {
            throw UpdaterError("Invalid flash-command acknowledgement; outcome is uncertain.")
        }
    }

    private func writeMailbox(_ address: UInt8, _ value: UInt8) async throws {
        let packet: [UInt8] = [0xBC, 0, 0, 0xB0, address, value]
        do {
            try await simpleAcknowledgement(packet, delay: 1)
        } catch is HIDResponseTimeout where address == 0xFF && [UInt8(0xF2), 0xF3, 0xD0].contains(value) {
            // FF selects the volatile I2C register page, never a flash commit.
            // The host rebinds the same registry ID, serial and location. Do not
            // insert a scaler query here: it may disturb a pending completion
            // mailbox. Reselect once, then require the original dependent ACKs.
            // E2=87 and every staging/commit command remain non-retriable.
            try await session.reopenAfterReplyTimeout()
            try await simpleAcknowledgement(packet, delay: 1)
        }
    }

    private func simpleAcknowledgement(_ payload: [UInt8], delay: UInt64) async throws {
        let reply = try await exchange(payload, delay: delay)
        guard reply == (try MonitorProtocol.report(4, [payload[0], 1])) else {
            throw UpdaterError("Invalid programming/setup acknowledgement; stop without retry.")
        }
    }

    private func sendFragment(_ payload: [UInt8]) async throws {
        _ = try await session.exchange(MonitorProtocol.report(4, payload), expectsReply: false)
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
        try await exchange([opcode, 0x6F, 0] + body + [Self.xor(body)], delay: delay)
    }

    private func exchange(_ payload: [UInt8], delay: UInt64 = 0) async throws -> [UInt8] {
        let reply = try await session.exchange(MonitorProtocol.report(4, payload))
        guard reply.count == 64, reply[0] == 4, reply[1] == payload[0], reply[2] != 0 else {
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

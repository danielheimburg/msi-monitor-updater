import Foundation

/// Normal-mode information used both before an update and for its final verification.
struct MonitorInformation: Codable, Equatable, Sendable {
    let usbSerial: String
    let location: Int
    let registryID: UInt64
    let model: UInt8
    let version: String
    let calibration: [UInt8]
    let serial: [UInt8]
}

struct MonitorProtocol: Sendable {
    let session: HIDSession

    static func inspect(_ identity: MonitorDevice) async throws -> MonitorInformation {
        let session = try HIDSession(identity: identity)
        do {
            let information = try await Self(session: session).information(identity: identity)
            await session.close()
            return information
        } catch {
            await session.close()
            throw error
        }
    }

    static func report(_ id: UInt8, _ payload: [UInt8], fill: UInt8 = 0) throws -> [UInt8] {
        guard payload.count <= 63 else { throw UpdaterError("Monitor command exceeds one HID report.") }
        return [id] + payload + Array(repeating: fill, count: 63 - payload.count)
    }

    func information(identity: MonitorDevice) async throws -> MonitorInformation {
        let modelData = try await read("5800140\r", header: "5b00140", count: 3)
        guard modelData == [0x30, 0x30, 0x90] else {
            throw UpdaterError("The controller does not identify a MEG342C monitor.")
        }
        let versionData = try await read("58001<0\r", header: "5b001<0", count: 3)
        guard versionData.allSatisfy({ (0x30...0x39).contains($0) }) else {
            throw UpdaterError("The monitor returned an invalid firmware version.")
        }
        let calibration = try await read("580[000\r", header: "5b00[", count: 12, checksum: true)
        let serial = try await read("5800131\r", header: "5b00131", count: 13, checksum: true)
        return MonitorInformation(usbSerial: identity.serial, location: identity.location,
            registryID: identity.id, model: modelData[2], version: String(decoding: versionData, as: UTF8.self),
            calibration: calibration, serial: serial)
    }

    /// Vendor C0 preservation transaction. The caller must use freshly acquired,
    /// durably saved data from this same monitor, after verified programming/reset.
    /// An uncertain acknowledgement stops the transaction without replay.
    func restore(_ information: MonitorInformation) async throws {
        guard information.model == 0x90, information.calibration.count == 12,
              information.serial.count == 13 else {
            throw UpdaterError("Invalid monitor preservation data.")
        }
        let setup: [UInt8] = [0x35, 0x62, 0x30, 0x30, 0x5A, 0xA5, 0x55, 0xAA, 0x30, 0x30, 0x0D]
        let finish: [UInt8] = [0x35, 0x62, 0x30, 0x30, 0x5A, 0xA8, 0xAA, 0x55, 0x30, 0x30, 0x0D]
        let color = Array("5b001i".utf8) + information.calibration
            + [information.calibration.reduce(UInt8(0), &+)] + Array("000000\r".utf8)
        let serial = Array("5b001j".utf8) + information.serial
            + [information.serial.reduce(UInt8(0), &+)] + Array("00000\r".utf8)
        let acknowledgement = try Self.report(1, Array("5600+\r".utf8))
        for payload in [setup, color, serial, finish] {
            guard try await session.exchange(Self.report(1, payload)) == acknowledgement else {
                throw UpdaterError("Preservation restore was not acknowledged; do not retry automatically.")
            }
        }
    }

    func requireReadyForRestore() async throws {
        let reply = try await session.exchange(Self.report(1, Array("5800100\r".utf8)))
        guard reply == (try Self.report(1, Array("5b00100001\r".utf8))) else {
            throw UpdaterError("The monitor is not ready for preservation restoration.")
        }
    }

    private func read(_ command: String, header: String, count: Int, checksum: Bool = false) async throws -> [UInt8] {
        let reply = try await session.exchange(Self.report(1, Array(command.utf8)))
        let prefix = [UInt8(1)] + Array(header.utf8)
        let end = prefix.count + count
        let terminator = end + (checksum ? 1 : 0)
        guard reply.starts(with: prefix), reply[terminator] == 0x0D,
              reply[(terminator + 1)...].allSatisfy({ $0 == 0 }) else {
            throw UpdaterError("Unexpected reply to \(command.trimmingCharacters(in: .newlines)); no further commands sent.")
        }
        let data = Array(reply[prefix.count..<end])
        if checksum && reply[end] != data.reduce(UInt8(0), &+) {
            throw UpdaterError("Monitor preservation-data checksum is invalid.")
        }
        return data
    }
}

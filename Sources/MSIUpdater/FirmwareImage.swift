import CryptoKit
import Darwin
import Foundation

struct UpdaterError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}

/// The scaler's internal programming link, distinct from the normal-mode
/// controller interface that also uses selector zero.
enum ScalerTransport: UInt8, Sendable {
    case uart = 0
    case i2c = 1

    var reportID: UInt8 { self == .uart ? 2 : 4 }
    var name: String { self == .uart ? "UART" : "I2C" }
    var displayName: String { self == .uart ? "UART" : "I²C" }
}

/// Parses the supported Novatek image envelope. A whole-file hash identifies the
/// transaction record; it never admits an image or supplies its model/version.
struct FirmwareImage: Sendable {
    static let blockSize = 4096
    static let bankSize = 0x1000000

    struct ModelProfile: Sendable {
        let modelName: String
        let modelCode: UInt8
        let transport: ScalerTransport
        let loaderDigests: [String: String]
        var panels: [String: String] = [:]
        var bootCodeLength: Int { modelCode == 0x90 ? 0x1400 : 0x6000 }
    }

    struct Partition: Sendable {
        let offset: Int
        let length: Int
    }

    let url: URL
    let bytes: [UInt8]
    let sha256: String
    let profile: ModelProfile
    let partitions: [Partition]
    let version: String
    let panel: String
    let loaderDigest: String
    var paddedLength: Int { (bytes.count + Self.blockSize - 1) / Self.blockSize * Self.blockSize }

    init(url: URL) throws {
        // The descriptor binds validation and reading to one file, including
        // when its path is replaced. Nonblocking open also prevents a FIFO from
        // hanging before the regular-file check.
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw UpdaterError("Cannot open the firmware file: \(String(cString: strerror(errno))).") }
        defer { Darwin.close(descriptor) }
        var properties = stat()
        guard fstat(descriptor, &properties) == 0 else { throw UpdaterError("Cannot inspect the opened firmware file.") }
        guard properties.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              (0x8000...off_t(Self.bankSize)).contains(properties.st_size), properties.st_size % 512 == 0 else {
            throw UpdaterError("Firmware must be a regular, 512-byte-aligned image between 32 KiB and 16 MiB.")
        }
        let size = Int(properties.st_size)
        // Read one extra byte to reject growth without allocating an unbounded
        // replacement. The parsed transaction owns these immutable bytes.
        var bytes = [UInt8](repeating: 0, count: size + 1)
        var count = 0
        while count < bytes.count {
            let received = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!.advanced(by: count), buffer.count - count)
            }
            if received < 0 {
                if errno == EINTR { continue }
                throw UpdaterError("Cannot read the firmware file: \(String(cString: strerror(errno))).")
            }
            if received == 0 { break }
            count += received
        }
        guard count == size else { throw UpdaterError("The firmware file changed while it was being read.") }
        bytes.removeLast()
        let partitions = try Self.parsePartitions(Array(bytes[0x6000..<0x7000]), imageLength: bytes.count)
        guard bytes[0x6048..<0x8000].allSatisfy({ $0 == 0 }),
              let end = partitions.map({ $0.offset + $0.length }).max(),
              (end + 511) / 512 * 512 == bytes.count,
              bytes[end...].allSatisfy({ $0 == 0xFF }) else {
            throw UpdaterError("Firmware metadata, selector space or final partition padding is invalid.")
        }
        // Native record positions are fixed even when the final two are empty.
        let applicationOffset = Self.word(bytes, at: 0x6020)
        let applicationLength = Self.word(bytes, at: 0x6024)
        let application = applicationOffset..<(applicationOffset + applicationLength)
        let allBytes = 0..<bytes.count
        let modelMarkers = Self.offsets(of: [0x55, 0xAA, 0x66, 0x99] + Array("UART".utf8), in: bytes, range: allBytes)
        guard modelMarkers.count == 1, let modelMarker = modelMarkers.first,
              application.contains(modelMarker), modelMarker + 8 < application.upperBound,
              let profile = Self.modelProfiles.first(where: { $0.modelCode == bytes[modelMarker + 8] }) else {
            throw UpdaterError("Firmware has no unique supported model marker in its application partition.")
        }
        let versionMarkers = Self.offsets(of: [6] + Array("FW.".utf8), in: bytes, range: application)
        var versions: Set<String> = []
        for offset in versionMarkers {
            guard offset + 7 < application.upperBound, bytes[offset + 7] == 0,
                  bytes[(offset + 4)..<(offset + 7)].allSatisfy({ (48...57).contains($0) }) else {
                throw UpdaterError("Firmware contains a malformed version record.")
            }
            versions.insert(String(decoding: bytes[(offset + 4)..<(offset + 7)], as: UTF8.self))
        }
        guard versions.count == 1, let version = versions.first,
              let expectedLoader = profile.loaderDigests[String(version.prefix(1))] else {
            throw UpdaterError("Firmware version records disagree, are missing, or select an unsupported hardware branch.")
        }
        // Optional binary version records corroborate the application strings.
        for (signature, valueOffset, formatByte) in [("FWVER", 9, false), ("VERSION", 12, true)] {
            for offset in Self.offsets(of: [0x55, 0xAA, 0x66, 0x99] + Array(signature.utf8), in: bytes, range: allBytes) {
                guard offset + valueOffset + 1 < bytes.count,
                      (!formatByte || bytes[offset + valueOffset - 1] == 2),
                      bytes[offset + valueOffset] <= 9, bytes[offset + valueOffset + 1] < 100,
                      String(format: "%03d", Int(bytes[offset + valueOffset]) * 100 + Int(bytes[offset + valueOffset + 1])) == version else {
                    throw UpdaterError("Firmware binary and text version records disagree.")
                }
            }
        }
        var panels: Set<String> = []
        for offset in Self.offsets(of: [0x55, 0xAA, 0x66, 0x99] + Array("PANEL".utf8), in: bytes, range: application) {
            guard offset + 9 < application.upperBound else { throw UpdaterError("Truncated panel record.") }
            let length = Int(bytes[offset + 9])
            let start = offset + 10
            guard length > 0, start + length <= application.upperBound,
                  bytes[start..<(start + length)].allSatisfy({ (32...126).contains($0) }) else {
                throw UpdaterError("Invalid firmware panel record.")
            }
            panels.insert(String(decoding: bytes[start..<(start + length)], as: UTF8.self))
        }
        guard panels.count == 1, let panel = panels.first,
              profile.panels[String(version.prefix(1))].map({ $0 == panel }) ?? true else {
            throw UpdaterError("Firmware panel records disagree or do not match its hardware branch.")
        }
        // A release may change application code and layout without registration.
        // A changed loader still needs analysis of its boot/activation contract.
        let loaderDigest = Self.digest(Array(bytes.prefix(profile.bootCodeLength)))
        guard loaderDigest == expectedLoader else {
            throw UpdaterError("Firmware uses an unrecognized bootloader; its programming contract needs review.")
        }
        self.url = url
        self.bytes = bytes
        self.sha256 = Self.digest(bytes)
        self.profile = profile
        self.partitions = partitions
        self.version = version
        self.panel = panel
        self.loaderDigest = loaderDigest
    }

    /// Installed tables are validated against slot geometry, independently of
    /// destination-image partitions and release catalogs. Normal-mode reads supply
    /// the installed model/version; a table alone does not encode that identity.
    static func validMetadata(sector: [UInt8], imageBase: Int, bankSize: Int) -> Bool {
        guard sector.count == blockSize, imageBase == 0 || imageBase == bankSize,
              sector.last == 0 || sector.last == 0xAA,
              sector[72..<4095].allSatisfy({ $0 == 0 }) else { return false }
        var normalized = sector
        for index in 0..<9 {
            let position = index * 8
            let address = word(sector, at: position)
            guard address >= imageBase, address - imageBase < bankSize else { return false }
            let offset = address - imageBase
            for byte in 0..<4 {
                normalized[position + byte] = UInt8(truncatingIfNeeded: offset >> (24 - byte * 8))
            }
        }
        return (try? parsePartitions(normalized, imageLength: bankSize)) != nil
    }

    private static func parsePartitions(_ metadata: [UInt8], imageLength: Int) throws -> [Partition] {
        var partitions: [Partition] = []
        for index in 0..<9 {
            let offset = word(metadata, at: index * 8)
            let length = word(metadata, at: index * 8 + 4)
            if offset == 0 && length == 0 && index >= 7 { continue }
            guard length > 0, offset >= 0x8000, offset % 512 == 0,
                  offset <= imageLength, length <= imageLength - offset else {
                throw UpdaterError("Firmware partition \(index + 1) is outside the image or misaligned.")
            }
            partitions.append(Partition(offset: offset, length: length))
        }
        guard word(metadata, at: 0) == 0x10000, word(metadata, at: 8) == 0x20000,
              word(metadata, at: 32) == 0x108000 else {
            throw UpdaterError("Firmware does not use the supported nine-record application layout.")
        }
        let sorted = partitions.sorted { $0.offset < $1.offset }
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            guard previous.offset + previous.length <= next.offset else { throw UpdaterError("Firmware partitions overlap.") }
        }
        return partitions
    }

    func requireCompatible(with information: MonitorInformation) throws {
        guard information.model == profile.modelCode else { throw UpdaterError("The selected firmware belongs to a different monitor model.") }
        guard information.panel == panel else { throw UpdaterError("Read the monitor panel identity; it must match the selected firmware.") }
        guard information.version.count == 3, information.version.utf8.allSatisfy({ (48...57).contains($0) }),
              information.version.first == version.first else {
            throw UpdaterError("Firmware branches target different hardware and cannot be crossed.")
        }
    }

    func downgradeWarning(installedVersion: String) -> String? {
        guard version < installedVersion else { return nil }
        return "Downgrade: FW\(installedVersion) → FW\(version). Older firmware may change settings or behavior. Downgrades have not been hardware-validated; recovery is unavailable."
    }

    func block(at offset: Int) throws -> [UInt8] {
        guard offset >= 0, offset % Self.blockSize == 0, offset < paddedLength else { throw UpdaterError("Invalid firmware block address.") }
        let end = min(offset + Self.blockSize, bytes.count)
        return Array(bytes[offset..<end]) + Array(repeating: 0xFF, count: Self.blockSize - (end - offset))
    }

    func metadata(imageBase: Int, bankSize: Int = Self.bankSize) throws -> [UInt8] {
        guard imageBase == 0 || imageBase == bankSize else { throw UpdaterError("Unsupported firmware destination bank.") }
        var result = Array(bytes[0x6000..<0x7000])
        for index in 0..<9 {
            let position = index * 8
            let address = UInt32(Self.word(result, at: position) + imageBase)
            for byte in 0..<4 { result[position + byte] = UInt8(truncatingIfNeeded: address >> (24 - byte * 8)) }
        }
        result[4095] = 0xAA
        return result
    }

    private static func word(_ bytes: [UInt8], at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func offsets(of signature: [UInt8], in bytes: [UInt8], range: Range<Int>) -> [Int] {
        let data = Data(bytes)
        let pattern = Data(signature)
        var cursor = range.lowerBound
        var offsets: [Int] = []
        while cursor <= range.upperBound - signature.count,
              let found = data.range(of: pattern, in: cursor..<range.upperBound) {
            offsets.append(found.lowerBound)
            cursor = found.lowerBound + 1
        }
        return offsets
    }

    private static func digest(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
}

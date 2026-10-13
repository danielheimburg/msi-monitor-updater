import CryptoKit
import Foundation

struct UpdaterError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}

/// One supported image profile. Its digest binds every parsed field to the official firmware.
struct FirmwareImage: Sendable {
    static let reviewedDigest = "03db338acefd86cd41aa05539a69d8fff5708423e4896912f677cebb81ac7c8a"
    static let reviewedLength = 0x264400
    static let blockSize = 4096
    static let bankSize = 0x1000000

    struct Partition: Sendable {
        let offset: Int
        let length: Int
    }

    let url: URL
    let bytes: [UInt8]
    let sha256: String
    let partitions: [Partition]
    var version: String { "046" }
    var paddedLength: Int { (bytes.count + Self.blockSize - 1) / Self.blockSize * Self.blockSize }

    init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, size.fileSize == Self.reviewedLength else {
            throw UpdaterError("Select the reviewed MEG342C FW046 image (2,507,776 bytes).")
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == Self.reviewedLength, digest == Self.reviewedDigest else {
            throw UpdaterError("This firmware image has not been reviewed. Its SHA-256 does not match FW046.")
        }
        let bytes = Array(data)
        let marker: [UInt8] = [0x55, 0xAA, 0x66, 0x99, 0x55, 0x41, 0x52, 0x54, 0x90]
        guard Array(bytes[0x254628..<0x254628 + marker.count]) == marker else {
            throw UpdaterError("The MEG342C model marker is missing.")
        }
        var partitions: [Partition] = []
        for index in 0..<9 {
            let position = 0x6000 + index * 8
            let offset = bytes[position..<position + 4].reduce(0) { ($0 << 8) | Int($1) }
            let length = bytes[position + 4..<position + 8].reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, offset >= 0x8000, offset <= bytes.count,
                  length <= bytes.count - offset else {
                throw UpdaterError("Firmware partition \(index + 1) is outside the image.")
            }
            partitions.append(Partition(offset: offset, length: length))
        }
        let sorted = partitions.sorted { $0.offset < $1.offset }
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            guard previous.offset + previous.length <= next.offset else {
                throw UpdaterError("Firmware partitions overlap.")
            }
        }
        self.url = url
        self.bytes = bytes
        self.sha256 = digest
        self.partitions = partitions
    }

    func block(at offset: Int) throws -> [UInt8] {
        guard offset >= 0, offset % Self.blockSize == 0, offset < paddedLength else {
            throw UpdaterError("Invalid firmware block address.")
        }
        let end = min(offset + Self.blockSize, bytes.count)
        return Array(bytes[offset..<end]) + Array(repeating: 0xFF, count: Self.blockSize - (end - offset))
    }

    func metadata(imageBase: Int) throws -> [UInt8] {
        guard imageBase == 0 || imageBase == Self.bankSize else {
            throw UpdaterError("Unsupported firmware destination bank.")
        }
        var result = Array(bytes[0x6000..<0x7000])
        for (index, partition) in partitions.enumerated() {
            let address = UInt32(partition.offset + imageBase)
            for byte in 0..<4 {
                result[index * 8 + byte] = UInt8(truncatingIfNeeded: address >> (24 - byte * 8))
            }
        }
        result[4095] = 0xAA
        return result
    }
}

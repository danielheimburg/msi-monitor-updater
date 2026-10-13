import CryptoKit
import Foundation

/// Offline plan for the reviewed A500 / GD25Q256D 32MiB / FW046 profile.
/// The caller must establish that hardware profile and acquire these physical
/// ranges freshly and consistently. A plan neither authorizes nor performs I/O.
/// It is journal-encodable, but cannot be decoded into an executable plan: derive
/// it again from fresh bytes after interruption rather than replaying a journal.
/// Bank selection and mutation ordering are documented in
/// docs/firmware/boot-and-metadata.md and docs/msi/update-sequence.md.
struct UpdatePlan: Encodable, Sendable {
    static let bootCodeLength = 0x1400
    static let metadataAddresses = [0x6000, 0x7000, 0x1006000, 0x1007000]
    static let bootCodeAddresses = [0, 0x1000000]

    struct VerifiedRegion: Codable, Sendable {
        let address: Int
        let length: Int
        let sha256: String
    }

    /// Order is mandatory. Each operation requires verification before the next.
    /// Marker clearing is a 512-byte zero program, not a sector erase.
    enum Operation: Codable, Sendable {
        case invalidateDestinationMarker(address: Int)
        case programImageBlock(sourceOffset: Int, address: Int)
        case programMetadata(address: Int)
        case invalidatePreviousMarker(address: Int)

        var address: Int {
            switch self {
            case .invalidateDestinationMarker(let address),
                 .programMetadata(let address),
                 .invalidatePreviousMarker(let address):
                return address
            case .programImageBlock(_, let address):
                return address
            }
        }

        var length: Int {
            switch self {
            case .invalidateDestinationMarker, .invalidatePreviousMarker:
                return 512
            case .programImageBlock, .programMetadata:
                return FirmwareImage.blockSize
            }
        }
    }

    let imageSHA256: String
    let selectedBank: Int
    let destinationBank: Int
    let verifiedRegions: [VerifiedRegion]
    let metadataBytes: [UInt8]
    let operations: [Operation]

    /// Keys are absolute physical byte addresses, never EAR-relative offsets.
    /// Requires exactly four complete 4KiB sectors and two 5120-byte boot copies.
    init(image: FirmwareImage,
         metadataSectors: [Int: [UInt8]],
         bootCodeCopies: [Int: [UInt8]]) throws {
        guard image.sha256 == FirmwareImage.reviewedDigest,
              image.bytes.count == FirmwareImage.reviewedLength,
              Set(metadataSectors.keys) == Set(Self.metadataAddresses),
              Set(bootCodeCopies.keys) == Set(Self.bootCodeAddresses) else {
            throw UpdaterError("Planning requires the reviewed image and every physical metadata/boot range.")
        }

        var verifiedRegions: [VerifiedRegion] = []
        for address in Self.bootCodeAddresses {
            guard let bytes = bootCodeCopies[address],
                  bytes == Array(image.bytes.prefix(Self.bootCodeLength)) else {
                throw UpdaterError("A physical boot-code copy differs from the reviewed loader.")
            }
            verifiedRegions.append(Self.region(address, bytes))
        }
        for address in Self.metadataAddresses {
            guard let bytes = metadataSectors[address], bytes.count == FirmwareImage.blockSize,
                  bytes.last == 0 || bytes.last == 0xAA else {
                throw UpdaterError("A metadata sector is incomplete or has an unknown marker.")
            }
            verifiedRegions.append(Self.region(address, bytes))
        }
        guard let lower6000 = metadataSectors[0x6000],
              let lower7000 = metadataSectors[0x7000],
              let upper6000 = metadataSectors[0x1006000],
              let upper7000 = metadataSectors[0x1007000] else {
            throw UpdaterError("Physical metadata ranges are missing.")
        }
        let lowerMetadata = try image.metadata(imageBase: 0)
        let upperMetadata = try image.metadata(imageBase: FirmwareImage.bankSize)
        let clearedLower = Self.clearedMarkerPage(lowerMetadata)
        let clearedUpper = Self.clearedMarkerPage(upperMetadata)
        let erasedThenCleared = Array(repeating: UInt8(0xFF), count: 3584)
            + Array(repeating: UInt8(0), count: 512)

        let selectedBank: Int
        if lower6000.last == 0, lower7000.last == 0xAA {
            // The observed upper-image state, or the completed lower→upper
            // successor. Active descriptors must match in both banks in full.
            let recordedOldLowerDigest = "5724ec5882a7a350fed80cb3077c7093dc4248c3f3538ca7e2b4e9c18df35c9f"
            let knownInactiveLower = lower6000 == clearedLower
                || Self.digest(lower6000) == recordedOldLowerDigest
            guard lower7000 == upperMetadata, upper7000 == upperMetadata,
                  knownInactiveLower,
                  upper6000 == erasedThenCleared || upper6000 == clearedLower else {
                throw UpdaterError("Upper-image metadata or inactive-bank contents differ from the reviewed states.")
            }
            selectedBank = 1
        } else if lower6000.last == 0xAA, lower7000.last == 0 {
            guard lower6000 == lowerMetadata, lower7000 == clearedUpper else {
                throw UpdaterError("Lower-image descriptors or its cleared predecessor differ from FW046.")
            }
            // The vendor's upper→lower update changes only bank0 metadata.
            // The retained upper table is expected in that specific successor,
            // not evidence that the two banks may disagree arbitrarily.
            let expectedAsymmetricState = upper7000 == upperMetadata
                && (upper6000 == erasedThenCleared || upper6000 == clearedLower)
            let mirroredLowerState = upper6000 == lowerMetadata && upper7000 == clearedUpper
            guard expectedAsymmetricState || mirroredLowerState else {
                throw UpdaterError("The second bank is neither the reviewed retained upper image nor a matching lower mirror.")
            }
            selectedBank = 0
        } else {
            // Boot prefers7FFF, while the vendor erase selector prefers6FFF.
            // Both-AA and neither-AA therefore cannot be normal retry states.
            throw UpdaterError("Ambiguous firmware markers; stop instead of retrying an update.")
        }

        let destinationBank = 1 - selectedBank
        let destinationBase = destinationBank * FirmwareImage.bankSize
        let metadataOffset = destinationBank == 0 ? 0x6000 : 0x7000
        let previousMetadataOffset = destinationBank == 0 ? 0x7000 : 0x6000
        let clearOrder = destinationBank == 0 ? [1, 0] : [0, 1]
        var operations: [Operation] = []
        for bank in clearOrder {
            operations.append(.invalidateDestinationMarker(
                address: bank * FirmwareImage.bankSize + metadataOffset + 0xE00))
        }

        var dataBlockCount = 0
        for offset in stride(from: 0, to: image.paddedLength, by: FirmwareImage.blockSize) {
            let skip = destinationBank == 0 ? offset < 0x8000 : (0x6000..<0x8000).contains(offset)
            if skip { continue }
            operations.append(.programImageBlock(sourceOffset: offset, address: destinationBase + offset))
            dataBlockCount += 1
        }
        guard dataBlockCount == (destinationBank == 0 ? 605 : 611),
              image.paddedLength == 0x265000 else {
            throw UpdaterError("The firmware block layout differs from the reviewed plan.")
        }

        // With this loader, upper selection may begin during the bank0 metadata
        // write. Lower selection begins when bank0's old7FFF marker is cleared.
        // Neither change is an independently atomic activation operation.
        let metadataBanks = destinationBank == 0 ? [0] : [0, 1]
        for bank in metadataBanks {
            operations.append(.programMetadata(address: bank * FirmwareImage.bankSize + metadataOffset))
        }
        for bank in metadataBanks {
            operations.append(.invalidatePreviousMarker(
                address: bank * FirmwareImage.bankSize + previousMetadataOffset + 0xE00))
        }
        guard operations.allSatisfy({ $0.address >= 0 && $0.address + $0.length <= 0x2000000 }) else {
            throw UpdaterError("The update plan exceeds the verified physical flash capacity.")
        }

        self.imageSHA256 = image.sha256
        self.selectedBank = selectedBank
        self.destinationBank = destinationBank
        self.verifiedRegions = verifiedRegions
        self.metadataBytes = try image.metadata(imageBase: destinationBase)
        self.operations = operations
    }

    private static func clearedMarkerPage(_ sector: [UInt8]) -> [UInt8] {
        Array(sector.prefix(3584)) + Array(repeating: 0, count: 512)
    }

    private static func region(_ address: Int, _ bytes: [UInt8]) -> VerifiedRegion {
        VerifiedRegion(address: address, length: bytes.count, sha256: digest(bytes))
    }

    private static func digest(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
}

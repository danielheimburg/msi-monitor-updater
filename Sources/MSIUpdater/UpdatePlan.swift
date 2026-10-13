import CryptoKit
import Foundation

/// Offline plan for the reviewed A500 / GD25Q256D 32MiB / reviewed MEG342C profiles.
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
    let installedVersion: String
    let targetVersion: String
    let selectedBank: Int
    let destinationBank: Int
    let verifiedRegions: [VerifiedRegion]
    let expectedFinalRegions: [VerifiedRegion]
    let metadataBytes: [UInt8]
    let operations: [Operation]

    /// Keys are absolute physical byte addresses, never EAR-relative offsets.
    /// Requires exactly four complete 4KiB sectors and two 5120-byte boot copies.
    init(image: FirmwareImage, installedVersion: String,
         metadataSectors: [Int: [UInt8]],
         bootCodeCopies: [Int: [UInt8]]) throws {
        guard image.profile.isFlashSupported,
              FirmwareImage.reviewedProfiles.contains(where: { $0.version == installedVersion }),
              Set(metadataSectors.keys) == Set(Self.metadataAddresses),
              Set(bootCodeCopies.keys) == Set(Self.bootCodeAddresses) else {
            throw UpdaterError("Planning requires the reviewed image and every physical metadata/boot range.")
        }

        var verifiedRegions: [VerifiedRegion] = []
        for address in Self.bootCodeAddresses {
            guard let bytes = bootCodeCopies[address],
                  bytes.count == Self.bootCodeLength,
                  Self.digest(bytes) == FirmwareImage.reviewedLoaderDigest else {
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
        let erasedThenCleared = Array(repeating: UInt8(0xFF), count: 3584)
            + Array(repeating: UInt8(0), count: 512)
        func reviewedSector(_ sector: [UInt8], base: Int, marker: UInt8) -> Bool {
            sector.last == marker && FirmwareImage.metadataVersion(sector: sector, imageBase: base) != nil
        }
        // This one exact inactive predecessor was preserved in the original
        // FW046 device state. It never establishes an active installed version.
        let recordedOldLowerDigest = "5724ec5882a7a350fed80cb3077c7093dc4248c3f3538ca7e2b4e9c18df35c9f"
        let knownInactiveLower = reviewedSector(lower6000, base: 0, marker: 0)
            || (installedVersion == "046" && Self.digest(lower6000) == recordedOldLowerDigest)
        let knownInactiveUpper = upper6000 == erasedThenCleared
            || reviewedSector(upper6000, base: 0, marker: 0)

        let selectedBank: Int
        if lower6000.last == 0, lower7000.last == 0xAA {
            guard FirmwareImage.metadataVersion(sector: lower7000, imageBase: FirmwareImage.bankSize) == installedVersion,
                  upper7000 == lower7000, knownInactiveLower, knownInactiveUpper else {
                throw UpdaterError("Upper-image metadata disagrees with the installed version or an inactive sector is unknown.")
            }
            selectedBank = 1
        } else if lower6000.last == 0xAA, lower7000.last == 0 {
            guard FirmwareImage.metadataVersion(sector: lower6000, imageBase: 0) == installedVersion,
                  reviewedSector(lower7000, base: FirmwareImage.bankSize, marker: 0) else {
                throw UpdaterError("Lower-image metadata disagrees with the installed version or its predecessor is unknown.")
            }
            // Upper→lower writes leave the previous upper table untouched.
            // It must still be an exact reviewed sector, not a target-derived one.
            let expectedAsymmetricState = reviewedSector(upper7000, base: FirmwareImage.bankSize, marker: 0xAA)
                && lower7000 == Self.clearedMarkerPage(upper7000) && knownInactiveUpper
            let mirroredLowerState = upper6000 == lower6000 && upper7000 == lower7000
            guard expectedAsymmetricState || mirroredLowerState else {
                throw UpdaterError("The second bank is neither a reviewed retained upper image nor a matching lower mirror.")
            }
            selectedBank = 0
        } else {
            // Boot prefers7FFF, while the vendor erase selector prefers6FFF.
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

        for offset in stride(from: 0, to: image.paddedLength, by: FirmwareImage.blockSize) {
            let skip = destinationBank == 0 ? offset < 0x8000 : (0x6000..<0x8000).contains(offset)
            if skip { continue }
            operations.append(.programImageBlock(sourceOffset: offset, address: destinationBase + offset))
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
        guard image.paddedLength <= FirmwareImage.bankSize,
              operations.allSatisfy({ $0.address >= 0 && $0.address + $0.length <= 0x2000000 }) else {
            throw UpdaterError("The update plan exceeds the verified physical flash capacity.")
        }

        // Apply only the planned metadata mutations to the saved source sectors.
        // Untouched predecessor tables must remain byte-identical after the update.
        let metadataBytes = try image.metadata(imageBase: destinationBase)
        var finalMetadata = metadataSectors
        for operation in operations {
            switch operation {
            case .programMetadata(let address):
                finalMetadata[address] = metadataBytes
            case .invalidateDestinationMarker(let address), .invalidatePreviousMarker(let address):
                let sectorAddress = address - 0xE00
                guard let sector = finalMetadata[sectorAddress] else {
                    throw UpdaterError("A marker operation has no preserved metadata sector.")
                }
                finalMetadata[sectorAddress] = Self.clearedMarkerPage(sector)
            case .programImageBlock: break
            }
        }
        self.imageSHA256 = image.sha256
        self.installedVersion = installedVersion
        self.targetVersion = image.version
        var expectedFinalRegions: [VerifiedRegion] = []
        for address in Self.metadataAddresses {
            guard let bytes = finalMetadata[address] else {
                throw UpdaterError("Final metadata expectation is incomplete.")
            }
            expectedFinalRegions.append(Self.region(address, bytes))
        }
        for address in Self.bootCodeAddresses {
            guard let bytes = bootCodeCopies[address] else {
                throw UpdaterError("Final loader expectation is incomplete.")
            }
            expectedFinalRegions.append(Self.region(address, bytes))
        }
        self.expectedFinalRegions = expectedFinalRegions
        self.selectedBank = selectedBank
        self.destinationBank = destinationBank
        self.verifiedRegions = verifiedRegions
        self.metadataBytes = metadataBytes
        self.operations = operations
    }

    /// Exact postconditions derived before mutation, independent of a future plan.
    func verifyFinalLayout(metadataSectors: [Int: [UInt8]], bootCodeCopies: [Int: [UInt8]]) throws {
        guard Set(metadataSectors.keys) == Set(Self.metadataAddresses),
              Set(bootCodeCopies.keys) == Set(Self.bootCodeAddresses) else {
            throw UpdaterError("Final firmware ranges are incomplete.")
        }
        let ranges = metadataSectors.merging(bootCodeCopies) { first, _ in first }
        for expected in expectedFinalRegions {
            guard let bytes = ranges[expected.address], bytes.count == expected.length,
                  Self.digest(bytes) == expected.sha256 else {
                throw UpdaterError(String(format: "Final firmware bytes differ at physical %08X.", expected.address))
            }
        }
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

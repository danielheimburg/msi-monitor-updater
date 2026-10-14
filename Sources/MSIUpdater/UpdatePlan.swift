import CryptoKit
import Foundation

/// Offline dual-slot plan for compatible A500/A300 images and 8/16/32MiB layouts.
/// The caller must establish that hardware profile and acquire these physical
/// ranges freshly and consistently. A plan neither authorizes nor performs I/O.
/// It is journal-encodable, but cannot be decoded into an executable plan: derive
/// it again from fresh bytes after interruption rather than replaying a journal.
/// Bank selection and mutation ordering are documented in
/// docs/firmware/boot-and-metadata.md and docs/msi/update-sequence.md.
struct UpdatePlan: Encodable, Sendable {
    static let metadataAddresses = [0x6000, 0x7000, 0x1006000, 0x1007000]
    static let bootCodeAddresses = [0, 0x1000000]

    static func metadataAddresses(capacity: Int) -> [Int] {
        capacity > 0x1000000 ? metadataAddresses : [0x6000, 0x7000]
    }

    static func bootCodeAddresses(capacity: Int) -> [Int] {
        capacity > 0x1000000 ? bootCodeAddresses : [0]
    }

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

    let bootCodeLength: Int
    let flashCapacity: Int
    let imageSHA256: String
    let installedVersion: String
    let targetVersion: String
    let downgradeWarning: String?
    let selectedBank: Int
    let destinationBank: Int
    let verifiedRegions: [VerifiedRegion]
    let expectedFinalRegions: [VerifiedRegion]
    let metadataBytes: [UInt8]
    let operations: [Operation]

    /// Keys are absolute physical byte addresses, never EAR-relative offsets.
    /// Requires every metadata sector and boot range for the identified capacity.
    init(image: FirmwareImage, installedVersion: String,
         metadataSectors: [Int: [UInt8]],
         bootCodeCopies: [Int: [UInt8]], flashCapacity: Int = 0x2000000) throws {
        guard [0x800000, 0x1000000, 0x2000000].contains(flashCapacity) else {
            throw UpdaterError("No reviewed layout for this flash capacity.")
        }
        let bankSize = flashCapacity / 2
        let metadataAddresses = Self.metadataAddresses(capacity: flashCapacity)
        let bootCodeAddresses = Self.bootCodeAddresses(capacity: flashCapacity)
        guard installedVersion.count == 3, installedVersion.utf8.allSatisfy({ (48...57).contains($0) }),
              installedVersion.first == image.version.first,
              Set(metadataSectors.keys) == Set(metadataAddresses),
              Set(bootCodeCopies.keys) == Set(bootCodeAddresses) else {
            throw UpdaterError("Planning requires a compatible branch and every physical metadata/boot range.")
        }

        var verifiedRegions: [VerifiedRegion] = []
        for address in bootCodeAddresses {
            guard let bytes = bootCodeCopies[address],
                  bytes.count == image.profile.bootCodeLength,
                  Self.digest(bytes) == image.loaderDigest else {
                throw UpdaterError("A physical boot-code copy differs from the reviewed loader.")
            }
            verifiedRegions.append(Self.region(address, bytes))
        }
        for address in metadataAddresses {
            guard let bytes = metadataSectors[address], bytes.count == FirmwareImage.blockSize,
                  bytes.last == 0 || bytes.last == 0xAA else {
                throw UpdaterError("A metadata sector is incomplete or has an unknown marker.")
            }
            verifiedRegions.append(Self.region(address, bytes))
        }
        guard let lower6000 = metadataSectors[0x6000],
              let lower7000 = metadataSectors[0x7000],
              let upper6000 = metadataSectors[0x1006000] ?? metadataSectors[0x6000],
              let upper7000 = metadataSectors[0x1007000] ?? metadataSectors[0x7000] else {
            throw UpdaterError("Physical metadata ranges are missing.")
        }
        let erasedThenCleared = Array(repeating: UInt8(0xFF), count: 3584)
            + Array(repeating: UInt8(0), count: 512)
        func validSector(_ sector: [UInt8], base: Int, marker: UInt8) -> Bool {
            sector.last == marker && FirmwareImage.validMetadata(sector: sector, imageBase: base, bankSize: bankSize)
        }
        let blankSector = Array(repeating: UInt8(0), count: FirmwareImage.blockSize)
        func validInactive(_ sector: [UInt8], base: Int) -> Bool {
            sector == blankSector || sector == erasedThenCleared || validSector(sector, base: base, marker: 0)
        }
        let validInactiveLower = validInactive(lower6000, base: 0)
        let validInactiveUpper = validInactive(upper6000, base: 0)

        let selectedBank: Int
        if lower6000.last == 0, lower7000.last == 0xAA {
            guard FirmwareImage.validMetadata(sector: lower7000, imageBase: bankSize, bankSize: bankSize),
                  upper7000 == lower7000, validInactiveLower,
                  (flashCapacity <= 0x1000000 || validInactiveUpper) else {
                throw UpdaterError("Upper-image metadata or an inactive sector has an unsupported structure.")
            }
            selectedBank = 1
        } else if lower6000.last == 0xAA, lower7000.last == 0 {
            guard FirmwareImage.validMetadata(sector: lower6000, imageBase: 0, bankSize: bankSize),
                  validInactive(lower7000, base: bankSize) else {
                throw UpdaterError("Lower-image metadata or its predecessor has an unsupported structure.")
            }
            // Upper→lower writes leave the previous upper table untouched.
            // Validate its own descriptors, independently of the target image.
            let expectedAsymmetricState = validSector(upper7000, base: bankSize, marker: 0xAA)
                && lower7000 == Self.clearedMarkerPage(upper7000) && validInactiveUpper
            let mirroredLowerState = upper6000 == lower6000 && upper7000 == lower7000
            let blankUpperState = validInactive(upper6000, base: 0)
                && validInactive(upper7000, base: bankSize)
            guard expectedAsymmetricState || mirroredLowerState || blankUpperState else {
                throw UpdaterError("The second bank is neither a valid retained upper image nor a matching lower mirror.")
            }
            selectedBank = 0
        } else {
            // Boot prefers7FFF, while the vendor erase selector prefers6FFF.
            throw UpdaterError("Ambiguous firmware markers; stop instead of retrying an update.")
        }

        let destinationBank = 1 - selectedBank
        let destinationBase = destinationBank * bankSize
        let metadataOffset = destinationBank == 0 ? 0x6000 : 0x7000
        let previousMetadataOffset = destinationBank == 0 ? 0x7000 : 0x6000
        let clearOrder = flashCapacity <= 0x1000000 ? [0] : (destinationBank == 0 ? [1, 0] : [0, 1])
        var operations: [Operation] = []
        for bank in clearOrder {
            operations.append(.invalidateDestinationMarker(
                address: bank * 0x1000000 + metadataOffset + 0xE00))
        }

        for offset in stride(from: 0, to: image.paddedLength, by: FirmwareImage.blockSize) {
            let skip = destinationBase < 0x1000000 ? offset < 0x8000 : (0x6000..<0x8000).contains(offset)
            if skip { continue }
            operations.append(.programImageBlock(sourceOffset: offset, address: destinationBase + offset))
        }

        // With this loader, upper selection may begin during the bank0 metadata
        // write. Lower selection begins when bank0's old7FFF marker is cleared.
        // Neither change is an independently atomic activation operation.
        let metadataBanks = destinationBase < 0x1000000 ? [0] : [0, 1]
        for bank in metadataBanks {
            operations.append(.programMetadata(address: bank * 0x1000000 + metadataOffset))
        }
        for bank in metadataBanks {
            operations.append(.invalidatePreviousMarker(
                address: bank * 0x1000000 + previousMetadataOffset + 0xE00))
        }
        guard image.paddedLength <= bankSize,
              operations.allSatisfy({ $0.address >= 0 && $0.address + $0.length <= flashCapacity }) else {
            throw UpdaterError("The update plan exceeds the verified physical flash capacity.")
        }

        // Apply only the planned metadata mutations to the saved source sectors.
        // Untouched predecessor tables must remain byte-identical after the update.
        let metadataBytes = try image.metadata(imageBase: destinationBase, bankSize: bankSize)
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
        self.bootCodeLength = image.profile.bootCodeLength
        self.flashCapacity = flashCapacity
        self.imageSHA256 = image.sha256
        self.installedVersion = installedVersion
        self.targetVersion = image.version
        self.downgradeWarning = image.downgradeWarning(installedVersion: installedVersion)
        var expectedFinalRegions: [VerifiedRegion] = []
        for address in metadataAddresses {
            guard let bytes = finalMetadata[address] else {
                throw UpdaterError("Final metadata expectation is incomplete.")
            }
            expectedFinalRegions.append(Self.region(address, bytes))
        }
        for address in bootCodeAddresses {
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
        guard Set(metadataSectors.keys) == Set(Self.metadataAddresses(capacity: flashCapacity)),
              Set(bootCodeCopies.keys) == Set(Self.bootCodeAddresses(capacity: flashCapacity)) else {
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

import CryptoKit
import Foundation

struct UpdaterError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) { self.message = message }
}

/// Supported official images; each digest binds parsed fields to the analyzed artifact.
struct FirmwareImage: Sendable {
    static let blockSize = 4096
    static let bankSize = 0x1000000
    static let reviewedLoaderDigest = "e03120960d3ade1934a6b50b6361d5a0907e201bf9f339478c8d4fc710bc2b22"

    enum Backend: String, Sendable {
        case novatek = "Novatek / Nuvoton"
        case realtek = "Realtek I2C"
        case mediaTek = "MediaTek"
    }

    struct ReviewedProfile: Sendable {
        let modelName: String
        let modelCode: UInt8?
        let backend: Backend
        var isFlashSupported: Bool { backend == .novatek && loaderDigest != nil }
        var loaderDigest: String? { reviewedLoaderDigest ?? (modelCode == 0x90 ? FirmwareImage.reviewedLoaderDigest : nil) }
        var bootCodeLength: Int { modelCode == 0x90 ? 0x1400 : 0x6000 }
        let reviewedLoaderDigest: String?
        let requiredPanel: String?
        let sameBranchRequired: Bool
        let interface: UInt8

        let version: String
        let imageDigest: String
        let imageLength: Int
        let modelMarkerOffset: Int?
        let activeMetadataDigest: String?
        let clearedMetadataDigest: String?

        init(version: String, imageDigest: String, imageLength: Int, modelMarkerOffset: Int?,
             activeMetadataDigest: String? = nil, clearedMetadataDigest: String? = nil,
             modelName: String = "MEG 342C QD-OLED", modelCode: UInt8? = 0x90, backend: Backend = .novatek, loaderDigest: String? = nil,
             requiredPanel: String? = nil, sameBranchRequired: Bool = true, interface: UInt8 = 1) {
            self.version = version
            self.imageDigest = imageDigest
            self.imageLength = imageLength
            self.modelMarkerOffset = modelMarkerOffset
            self.activeMetadataDigest = activeMetadataDigest
            self.clearedMetadataDigest = clearedMetadataDigest
            self.modelName = modelName
            self.modelCode = modelCode
            self.backend = backend
            self.reviewedLoaderDigest = loaderDigest
            self.requiredPanel = requiredPanel
            self.sameBranchRequired = sameBranchRequired
            self.interface = interface
        }
    }

    // Metadata hashes cover all 4KiB with descriptor addresses normalized to bank0.
    // Cleared metadata has its entire last 512-byte marker page zeroed.
    static let megProfiles: [ReviewedProfile] = [
        ReviewedProfile(
            version: "033",
            imageDigest: "4cceb247b768578e983531f5127234be6a9c9886fd91291b778898097de68d9d",
            imageLength: 0x261E00, modelMarkerOffset: 0x251FB8,
            activeMetadataDigest: "d2c9652fc82752366d7721ba6d3020004dfc899e4a8ab243e62abd970d06d5b8",
            clearedMetadataDigest: "c781d1c57604e575e9e8a081d49f560ea0ab91711b9e6a2aabecb8b9b59cee03"),
        ReviewedProfile(
            version: "035",
            imageDigest: "33cec452cde01723c76470a670b70cd16d4c8ee4e4f178df4a4d5e73195d3f34",
            imageLength: 0x261E00, modelMarkerOffset: 0x251FC0,
            activeMetadataDigest: "96661656e1817158b00b995e201f4457cbae733cb1ae8ba1bc37657873f61db3",
            clearedMetadataDigest: "ed0812153cff9776bbb2e7458b760a87280ca5991c80be9fc2204a0b85121a1b"),
        ReviewedProfile(
            version: "040",
            imageDigest: "850012925fc66d65e6c3e9911618f6574a4b8bd5bbcc1911123f760110325e46",
            imageLength: 0x263E00, modelMarkerOffset: 0x253F88,
            activeMetadataDigest: "e597868211b6d22283d8bad7b39b50dd8de167d242a25df455e8cdf65dc20b39",
            clearedMetadataDigest: "6c4a3305933a552a54ab71511bb6fb5cab5f9aa22400a89bb50c6e655dbe3afd"),
        ReviewedProfile(
            version: "041",
            imageDigest: "50ef94cae78a8e301f114f1f1c4adf6f2ec1b799f797a3db43520a852f9b07f8",
            imageLength: 0x263E00, modelMarkerOffset: 0x253FE8,
            activeMetadataDigest: "aa92f1be7fd8b95b22da82cb9cc12a02413e56c6f4b955d57070d63c47f5e794",
            clearedMetadataDigest: "c4938ab905bc0ea3cb7a4438e213359c1429cac21c1446a41758d0a2eba21bc9"),
        ReviewedProfile(
            version: "044",
            imageDigest: "64835b7b344258608ca5a6ddb70e59e156470523afe3d66b9f9a90728ab2f6bc",
            imageLength: 0x264400, modelMarkerOffset: 0x254620,
            activeMetadataDigest: "e8844bfa00bdf612003004747c89a03c613deca22f239a05b637f0a32bc01677",
            clearedMetadataDigest: "90a814ffc956a200dbdc7e557bd76acead73cb0764fb2fcfe25f1b0e8355592a"),
        ReviewedProfile(
            version: "046",
            imageDigest: "03db338acefd86cd41aa05539a69d8fff5708423e4896912f677cebb81ac7c8a",
            imageLength: 0x264400, modelMarkerOffset: 0x254628,
            activeMetadataDigest: "f35f632faa017e7b8694419cfcfd63b99192e6e7d4e6cad0a8245e8008d48263",
            clearedMetadataDigest: "af1b9127b40c661bfaf9aa8d50aeee2c42c830b3d88d5818acab5646ddb825c6")
    ]

    // Each writer needs a reviewed image and loader contract. Other backends
    // remain inspection-only even when their USB identity is shared.
    static let reviewedProfiles = megProfiles + additionalProfiles
    static let inspectionProfiles: [ReviewedProfile] = reviewedProfiles + [
        ReviewedProfile(
            version: "033", imageDigest: "7ece5d07e3b8b0f528c7d5fbae2566162d5f4924ba5df18aeab0c278468ebe14",
            imageLength: 2057252, modelMarkerOffset: nil,
            modelName: "MAG 273QP QD-OLED X24", modelCode: nil, backend: .mediaTek),
        ReviewedProfile(
            version: "120", imageDigest: "b5f93752dbe94d04937d26bb68302e121f4f0bd78d34f1361a988da730e0e7c6",
            imageLength: 2057236, modelMarkerOffset: nil,
            modelName: "MAG 273QP QD-OLED X24", modelCode: nil, backend: .mediaTek),
        ReviewedProfile(
            version: "109", imageDigest: "1666f53a5b435d6bd233ce3f750cf32128880fe60e585592429651042ace1506",
            imageLength: 3670016, modelMarkerOffset: nil,
            modelName: "MPG 271QRX QD-OLED", modelCode: 0x9E, backend: .realtek),
        ReviewedProfile(
            version: "111", imageDigest: "e4403967d6b86440ade61dd7942edf8a42f00bb2c511d72da35a6ef4183f919a",
            imageLength: 3670016, modelMarkerOffset: nil,
            modelName: "MPG 271QRX QD-OLED", modelCode: 0x9E, backend: .realtek),
        ReviewedProfile(
            version: "024", imageDigest: "d02b5abb341079d3e726a13e8b8ccf6cb2c39be46e1443c1d0e0a436ee9c1345",
            imageLength: 3670016, modelMarkerOffset: nil,
            modelName: "MPG 322URX QD-OLED", modelCode: 0xAE, backend: .realtek)
    ]

    struct Partition: Sendable {
        let offset: Int
        let length: Int
    }

    let url: URL
    let bytes: [UInt8]
    let sha256: String
    let profile: ReviewedProfile
    let partitions: [Partition]
    var version: String { profile.version }
    var paddedLength: Int { (bytes.count + Self.blockSize - 1) / Self.blockSize * Self.blockSize }

    init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true,
              Self.inspectionProfiles.contains(where: { $0.imageLength == size.fileSize }) else {
            throw UpdaterError("Select an official firmware image from the reviewed catalog.")
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard let profile = Self.inspectionProfiles.first(where: {
            $0.imageDigest == digest && $0.imageLength == data.count
        }) else {
            throw UpdaterError("This firmware image has not been reviewed. Its SHA-256 is not in the supported image catalog.")
        }
        let bytes = Array(data)
        if let offset = profile.modelMarkerOffset, let modelCode = profile.modelCode {
            let marker: [UInt8] = [0x55, 0xAA, 0x66, 0x99, 0x55, 0x41, 0x52, 0x54, modelCode]
            guard offset >= 0, offset + marker.count <= bytes.count,
                  Array(bytes[offset..<offset + marker.count]) == marker else {
                throw UpdaterError("The reviewed model marker is missing.")
            }
        }
        // Opaque Realtek/MediaTek artifacts have no reviewed Novatek table.
        // Their digest/model/backend can be inspected, but never planned or flashed.
        let partitions = profile.backend == .novatek
            ? try Self.parsePartitions(Array(bytes[0x6000..<0x7000]), imageLength: bytes.count) : []
        self.url = url
        self.bytes = bytes
        self.sha256 = digest
        self.profile = profile
        self.partitions = partitions
    }

    /// Recognizes installed tables independently of the chosen destination file.
    /// Unknown markers, relocation underflow and malformed ranges are rejected.
    static func metadataVersions(sector: [UInt8], imageBase: Int, modelCode: UInt8 = 0x90,
                                bankSize: Int = Self.bankSize) -> Set<String> {
        guard sector.count == blockSize, imageBase == 0 || imageBase == bankSize,
              sector.last == 0 || sector.last == 0xAA else { return [] }
        var normalized = sector
        for index in 0..<9 {
            let position = index * 8
            let address = sector[position..<position + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard address >= imageBase else { return [] }
            let offset = address - imageBase
            guard offset < bankSize else { return [] }
            for byte in 0..<4 {
                normalized[position + byte] = UInt8(truncatingIfNeeded: offset >> (24 - byte * 8))
            }
        }
        guard (try? parsePartitions(normalized, imageLength: bankSize)) != nil else { return [] }
        let digest = SHA256.hash(data: Data(normalized)).map { String(format: "%02x", $0) }.joined()
        return Set(reviewedProfiles.filter {
            $0.modelCode == modelCode && digest == (sector.last == 0xAA ? $0.activeMetadataDigest : $0.clearedMetadataDigest)
        }.map(\.version))
    }

    private static func parsePartitions(_ metadata: [UInt8], imageLength: Int) throws -> [Partition] {
        var partitions: [Partition] = []
        for index in 0..<9 {
            let position = index * 8
            let offset = metadata[position..<position + 4].reduce(0) { ($0 << 8) | Int($1) }
            let length = metadata[position + 4..<position + 8].reduce(0) { ($0 << 8) | Int($1) }
            if offset == 0 && length == 0 { continue }
            guard length > 0, offset >= 0x8000, offset <= imageLength,
                  length <= imageLength - offset else {
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
        guard !partitions.isEmpty else { throw UpdaterError("Firmware has no populated partitions.") }
        return partitions
    }

    /// Version policy is checked by both the GUI and writer before ISP entry.
    /// An accepted profile does not constitute hardware validation of a transition.
    func requireCompatible(with information: MonitorInformation) throws {
        guard information.model == profile.modelCode else {
            throw UpdaterError("The selected firmware belongs to a different monitor model.")
        }
        guard profile.requiredPanel == nil || information.panel == profile.requiredPanel else {
            throw UpdaterError("The monitor panel does not match this firmware branch.")
        }
        try requireUpdateAllowed(installedVersion: information.version)
    }

    func requireUpdateAllowed(installedVersion: String) throws {
        guard profile.isFlashSupported else {
            throw UpdaterError("This model has offline image inspection only; flashing is unsupported.")
        }
        guard Self.reviewedProfiles.contains(where: {
            $0.modelCode == profile.modelCode && $0.version == installedVersion
                && $0.loaderDigest == profile.loaderDigest
        }) else {
            throw UpdaterError("The installed firmware version has no reviewed metadata profile.")
        }
        guard !profile.sameBranchRequired || installedVersion.first == version.first else {
            throw UpdaterError("Firmware branches target different hardware and cannot be crossed.")
        }
        guard installedVersion <= version else {
            throw UpdaterError("Downgrades are not hardware-validated and remain disabled.")
        }
    }

    func block(at offset: Int) throws -> [UInt8] {
        guard offset >= 0, offset % Self.blockSize == 0, offset < paddedLength else {
            throw UpdaterError("Invalid firmware block address.")
        }
        let end = min(offset + Self.blockSize, bytes.count)
        return Array(bytes[offset..<end]) + Array(repeating: 0xFF, count: Self.blockSize - (end - offset))
    }

    func metadata(imageBase: Int, bankSize: Int = Self.bankSize) throws -> [UInt8] {
        guard profile.isFlashSupported, imageBase == 0 || imageBase == bankSize else {
            throw UpdaterError("Unsupported firmware destination bank.")
        }
        var result = Array(bytes[0x6000..<0x7000])
        // The native A500/A300 path relocates all nine records, including empty
        // zero-length slots. Keep their table positions rather than compacting.
        for index in 0..<9 {
            let position = index * 8
            let offset = bytes[(0x6000 + position)..<(0x6004 + position)].reduce(0) { ($0 << 8) | Int($1) }
            let address = UInt32(offset + imageBase)
            for byte in 0..<4 {
                result[position + byte] = UInt8(truncatingIfNeeded: address >> (24 - byte * 8))
            }
        }
        result[4095] = 0xAA
        return result
    }
}

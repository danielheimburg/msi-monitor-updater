import Foundation

/// One fresh, device-bound update. Records describe what happened; they cannot
/// be replayed. No cancellation/retry/reset is attempted after uncertain mutation.
struct FirmwareUpdate: Encodable, Sendable {
    enum Progress: Sendable {
        case preparing(String)
        case programming(completed: Int, total: Int)
        case verifying
        case restarting
        case restoring
        case complete(String)

        var message: String {
            switch self {
            case .preparing(let message): message
            case .programming(let completed, let total): "Verified \(completed) of \(total) update operations"
            case .verifying: "Checking final firmware metadata and boot code"
            case .restarting: "Restarting the monitor and waiting for USB reconnection"
            case .restoring: "Restoring and checking calibration and serial data"
            case .complete(let version): "FW\(version) verified; calibration and serial preserved"
            }
        }
    }

    struct Failure: LocalizedError, Sendable {
        let message: String
        let recordDirectory: URL
        var errorDescription: String? { message }
    }

    let information: MonitorInformation
    let destinationBank: Int
    let recordDirectory: URL

    static func run(image: FirmwareImage, device: MonitorDevice, parent: URL, confirmedVersion: String? = nil,
                    progress: @escaping @Sendable (Progress) async -> Void) async throws -> Self {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .suddenTerminationDisabled],
            reason: "Update MSI monitor firmware")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let record = try UpdateRecord(parent: parent)
        let session = try HIDSession(identity: device, record: record)
        var entered = false
        var mutationStarted = false
        do {
            await progress(.preparing("Reading monitor identity and saving calibration"))
            let information = try await MonitorProtocol(session: session).information(identity: device)
            guard try await MonitorProtocol(session: session).information(identity: device) == information else {
                throw UpdaterError("Repeated monitor identity or preservation reads disagree.")
            }
            try image.requireCompatible(with: information)
            guard confirmedVersion == nil || confirmedVersion == information.version else {
                throw UpdaterError("The installed version changed after confirmation. Read monitor information and confirm again.")
            }
            if let warning = image.downgradeWarning(installedVersion: information.version) {
                await progress(.preparing(warning))
                try record.append("downgrade-warning", detail: warning, durable: true)
            }
            try record.preserve("monitor.json", data: JSONEncoder().encode(information))
            try record.preserve("calibration.bin", data: Data(information.calibration))
            try record.preserve("serial.bin", data: Data(information.serial))
            try record.append("entering-isp", durable: true)
            entered = true
            try await UpdatePreparation.enterISP(session, interface: image.profile.interface)
            let isp = try await ScalerISP.connect(session: session, interface: image.profile.interface)
            try record.preserve("hardware.json", data: JSONEncoder().encode(isp.hardware))
            await progress(.preparing("Preserving boot code and firmware metadata"))
            let plan = try await UpdatePreparation.acquirePlan(image: image, installedVersion: information.version, isp: isp, record: record) { message in await progress(.preparing(message)) }
            // The upper branch also overwrites the rest of its first six blocks.
            // Require and preserve the pinned contents across that entire area.
            if plan.destinationBank == 1 && isp.hardware.capacity > 0x1000000 && plan.bootCodeLength < 0x6000 {
                await progress(.preparing("Preserving and checking the remaining boot area"))
                let address = FirmwareImage.bankSize + plan.bootCodeLength
                let count = 0x6000 - plan.bootCodeLength
                let bytes = try await isp.readPhysical(address: UInt32(address), count: count)
                guard bytes == Array(image.bytes[plan.bootCodeLength..<0x6000]) else {
                    throw UpdaterError("The upper boot area differs from the pinned image; stop before overwriting it.")
                }
                try record.preserve("upper-boot-area-tail.bin", data: Data(bytes))
            }
            try Task.checkCancellation()
            try record.append("protection-change-intent", durable: true)
            // Set before submission: a lost reply cannot make this diagnostic-only.
            mutationStarted = true
            try await isp.initializeProgramming()
            try record.append("protection-change-verified", durable: true)
            var selectedBank: Int?
            for (index, operation) in plan.operations.enumerated() {
                let bank = operation.address / FirmwareImage.bankSize
                let address = UInt32(operation.address % FirmwareImage.bankSize)
                if selectedBank != bank {
                    try await isp.selectBank(UInt8(bank))
                    if isp.hardware.capacity > 0x1000000 {
                        guard try await isp.readStatus(.extendedAddress) == UInt8(bank) else {
                            throw UpdaterError("The flash address bank does not match the next operation.")
                        }
                    }
                    selectedBank = bank
                }
                await progress(.programming(completed: index, total: plan.operations.count))
                let bytes: [UInt8]
                switch operation {
                case .programImageBlock(let offset, _): bytes = try image.block(at: offset)
                case .programMetadata: bytes = plan.metadataBytes
                case .invalidateDestinationMarker, .invalidatePreviousMarker:
                    bytes = Array(repeating: 0, count: 512)
                }
                let detail = String(format: "%d physical=%08X bytes=%d", index, operation.address, bytes.count)
                let intent = image.profile.interface == 0 && bytes.count == FirmwareImage.blockSize
                    ? "erase-program-sector-intent" : "program-intent"
                try record.append(intent, detail: detail, durable: true)
                if bytes.count == FirmwareImage.blockSize {
                    try await isp.programBlock(address: address, bytes: bytes)
                } else {
                    try await isp.programPage(address: address, bytes: bytes)
                }
                try record.append("program-page-checksums-verified", detail: detail, durable: true)
                // Independently address the physical bank at its first image block.
                // Metadata and marker operations additionally require exact readback.
                let needsPhysicalRead: Bool
                switch operation {
                case .programImageBlock(let offset, _):
                    needsPhysicalRead = offset == (plan.destinationBank == 1 && isp.hardware.capacity > 0x1000000 ? 0 : 0x8000)
                default: needsPhysicalRead = true
                }
                if needsPhysicalRead {
                    guard try await isp.readPhysical(address: UInt32(operation.address), count: bytes.count) == bytes else {
                        throw UpdaterError("Physical flash readback differs from the submitted data.")
                    }
                    try record.append("physical-readback-verified", detail: detail, durable: true)
                }
                await progress(.programming(completed: index + 1, total: plan.operations.count))
            }
            await progress(.verifying)
            try await verifyFinalLayout(plan: plan, isp: isp, record: record)
            try record.append("all-programming-verified-reset-intent", durable: true)
            await progress(.restarting)
            let returned = try await UpdatePreparation.resetAndReacquire(session, previous: device, interface: image.profile.interface)
            entered = false
            await progress(.restoring)
            let restored = try await restoreAndVerify(information, image: image, device: returned, record: record)
            try record.append("update-complete", durable: true)
            await progress(.complete(restored.version))
            return Self(information: restored, destinationBank: plan.destinationBank, recordDirectory: record.directory)
        } catch {
            await session.close()
            var failure = error.localizedDescription
            if entered && !mutationStarted {
                // No flash/protection writes: reuse diagnostic exit, independent
                // of caller cancellation and any failed evidence storage.
                let cleanupError = await UpdatePreparation.exitFailedDiagnostic(device, interface: image.profile.interface)
                if let cleanupError {
                    failure += " Diagnostic exit could not be verified: \(cleanupError)"
                    try? record.append("diagnostic-exit-unverified", detail: cleanupError, durable: true)
                }
            }
            try? record.append(mutationStarted ? "update-incomplete-no-retry" : "preflight-failed-no-flash",
                               detail: failure, durable: true)
            let boundary = mutationStarted
                ? "No retry or recovery was attempted. Keep the monitor connected; inspect this record before further action."
                : "No firmware or protection write was submitted."
            throw Failure(message: "\(failure) \(boundary)", recordDirectory: record.directory)
        }
    }

    private static func verifyFinalLayout(plan: UpdatePlan,
                                          isp: ScalerISP, record: UpdateRecord) async throws {
        var sectors: [Int: [UInt8]] = [:]
        var loaders: [Int: [UInt8]] = [:]
        for address in UpdatePlan.metadataAddresses(capacity: isp.hardware.capacity) {
            let bytes = try await isp.readPhysical(address: UInt32(address), count: FirmwareImage.blockSize)
            sectors[address] = bytes
            try record.preserve(String(format: "final-metadata-%08X.bin", address), data: Data(bytes))
        }
        for address in UpdatePlan.bootCodeAddresses(capacity: isp.hardware.capacity) {
            let bytes = try await isp.readPhysical(address: UInt32(address), count: plan.bootCodeLength)
            loaders[address] = bytes
            try record.preserve(String(format: "final-loader-%08X.bin", address), data: Data(bytes))
        }
        try plan.verifyFinalLayout(metadataSectors: sectors, bootCodeCopies: loaders)
    }

    private static func restoreAndVerify(_ original: MonitorInformation, image: FirmwareImage,
                                          device: MonitorDevice, record: UpdateRecord) async throws -> MonitorInformation {
        let session = try HIDSession(identity: device, record: record)
        do {
            try await UpdatePreparation.selectInterface(0, session: session)
            let normal = MonitorProtocol(session: session)
            try await normal.requireReadyForRestore()
            let beforeRestore = try await normal.information(identity: device)
            guard beforeRestore.model == original.model, beforeRestore.panel == original.panel, beforeRestore.version == image.version else {
                throw UpdaterError("Post-reset model or firmware does not match the requested update.")
            }
            try record.append("preservation-restore-intent", durable: true)
            try await normal.restore(original)
            let after = try await normal.information(identity: device)
            guard after.model == original.model, after.panel == original.panel, after.version == image.version,
                  after.calibration == original.calibration, after.serial == original.serial else {
                throw UpdaterError("Post-update firmware, calibration or serial verification failed.")
            }
            try record.preserve("postflight.json", data: JSONEncoder().encode(after))
            await session.close()
            return after
        } catch { await session.close(); throw error }
    }
}

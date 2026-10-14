import Foundation

/// Acquires and verifies a device-bound preparation record, then leaves ISP.
/// No flash-array or protection writes occur here. A later writer must derive
/// its plan again from fresh state; this result is a preview, never a resume token.
struct UpdatePreparation: Encodable, Sendable {
    let information: MonitorInformation
    let plan: UpdatePlan
    let recordDirectory: URL

    static func run(image: FirmwareImage, device: MonitorDevice, parent: URL) async throws -> Self {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .suddenTerminationDisabled],
            reason: "Read and preserve MSI firmware metadata")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let record = try UpdateRecord(parent: parent)
        var acquiredSession: HIDSession?
        var entered = false
        do {
            let session = try HIDSession(identity: device, record: record)
            acquiredSession = session
            let information = try await MonitorProtocol(session: session).information(identity: device)
            guard try await MonitorProtocol(session: session).information(identity: device) == information else {
                throw UpdaterError("Repeated monitor identity or preservation reads disagree.")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try await record.preserve("monitor.json", data: encoder.encode(information))
            try await record.preserve("calibration.bin", data: Data(information.calibration))
            try await record.preserve("serial.bin", data: Data(information.serial))
            try image.requireCompatible(with: information)
            try await record.append("entering-diagnostic-isp", durable: true)
            // An uncertain entry still requires diagnostic cleanup. This path
            // never submitted a destructive command, so A1 is appropriate here.
            entered = true
            try await enterISP(session, transport: image.profile.transport)
            let isp = try await ScalerISP.connect(session: session, transport: image.profile.transport)
            try await record.preserve("hardware.json", data: JSONEncoder().encode(isp.hardware))
            let plan = try await acquirePlan(image: image, installedVersion: information.version, isp: isp, record: record)
            try await record.append("diagnostic-reads-verified", durable: true)
            let reacquired = try await resetAndReacquire(session, previous: device, transport: image.profile.transport)
            entered = false
            let after = try await MonitorProtocol.inspect(reacquired)
            guard after.model == information.model, after.panel == information.panel, after.version == information.version,
                  after.calibration == information.calibration, after.serial == information.serial else {
                throw UpdaterError("Monitor data changed across diagnostic preparation.")
            }
            try await record.preserve("postflight.json", data: encoder.encode(after))
            try await record.append("preparation-complete-no-flash", durable: true)
            return Self(information: information, plan: plan, recordDirectory: record.directory)
        } catch {
            var failure = error.localizedDescription
            await acquiredSession?.close()
            if entered {
                // Cleanup must survive caller cancellation and unavailable storage.
                // It runs only for this diagnostic path, which never writes flash.
                let cleanupFailure = await exitFailedDiagnostic(device, transport: image.profile.transport)
                if let cleanupFailure {
                    try? await record.append("diagnostic-exit-unverified", detail: cleanupFailure, durable: true)
                    failure += " Diagnostic exit could not be verified: \(cleanupFailure)"
                }
            }
            try? await record.append("preparation-failed-no-flash", detail: failure, durable: true)
            throw UpdateRecord.Failure(message: failure, recordDirectory: record.directory)
        }
    }

    /// Isolated from caller cancellation and failed journal storage. This may
    /// reset only a diagnostic session that has submitted no protection/flash write.
    static func exitFailedDiagnostic(_ previous: MonitorDevice, transport: ScalerTransport) async -> String? {
        await Task.detached { () -> String? in
            do {
                let current = try matchingDevice(previous)
                let normal: MonitorDevice
                if current.id == previous.id {
                    let cleanup = try HIDSession(identity: current)
                    normal = try await resetAndReacquire(cleanup, previous: current, transport: transport)
                } else {
                    // A fresh service may already be in normal mode. Never send
                    // an ISP command merely because an earlier service failed.
                    normal = current
                }
                _ = try await MonitorProtocol.inspect(normal)
                return nil
            } catch { return error.localizedDescription }
        }.value
    }

    static func acquirePlan(image: FirmwareImage, installedVersion: String, isp: ScalerISP, record: UpdateRecord,
                            progress: @Sendable (String) async -> Void = { _ in }) async throws -> UpdatePlan {
        let originalBank = isp.hardware.capacity > 0x1000000 ? try await isp.readStatus(.extendedAddress) : 0
        guard originalBank <= 1 else { throw UpdaterError("Unexpected flash address-bank state.") }
        var metadata: [Int: [UInt8]] = [:]
        var loaders: [Int: [UInt8]] = [:]
        let bootAddresses = UpdatePlan.bootCodeAddresses(capacity: isp.hardware.capacity)
        for (index, address) in bootAddresses.enumerated() {
            await progress("Preserving boot code \(index + 1) of \(bootAddresses.count)")
            loaders[address] = try await acquire(address, count: image.profile.bootCodeLength, isp: isp, record: record)
        }
        let metadataAddresses = UpdatePlan.metadataAddresses(capacity: isp.hardware.capacity)
        for (index, address) in metadataAddresses.enumerated() {
            await progress("Preserving firmware metadata \(index + 1) of \(metadataAddresses.count)")
            metadata[address] = try await acquire(address, count: FirmwareImage.blockSize, isp: isp, record: record)
        }
        if isp.hardware.capacity > 0x1000000 {
            guard try await isp.readStatus(.extendedAddress) == originalBank else {
                throw UpdaterError("Flash address bank changed during preservation.")
            }
        }
        let plan = try UpdatePlan(image: image, installedVersion: installedVersion, metadataSectors: metadata, bootCodeCopies: loaders, flashCapacity: isp.hardware.capacity)
        try await record.preserve("plan.json", data: JSONEncoder().encode(plan))
        return plan
    }

    private static func acquire(_ address: Int, count: Int, isp: ScalerISP, record: UpdateRecord) async throws -> [UInt8] {
        let name = String(format: "physical-%08X.bin", address)
        try await record.append("reading-preservation", detail: name)
        // UpdatePlan checks boot bytes against the pinned loader and validates
        // metadata structure and bank relationships before deriving any write.
        let bytes = try await isp.readPhysical(address: UInt32(address), count: count)
        try await record.preserve(name, data: Data(bytes))
        return bytes
    }

    static func selectInterface(_ interface: UInt8, session: HIDSession) async throws {
        let reply = try await session.exchange(MonitorProtocol.report(1, [0xE0, interface], fill: 0xFF))
        guard reply == [1, 0x5A, interface] + Array(repeating: 0xFF, count: 61) else {
            throw UpdaterError("Controller interface selection was not acknowledged.")
        }
    }

    static func enterISP(_ session: HIDSession, transport: ScalerTransport) async throws {
        if transport == .uart {
            try await selectInterface(transport.rawValue, session: session)
            return
        }
        _ = try await session.exchange(MonitorProtocol.report(1, Array("580040:\r".utf8)), expectsReply: false)
        try await Task.sleep(for: .milliseconds(200))
        try await selectInterface(transport.rawValue, session: session)
        try await Task.sleep(for: .seconds(2))
    }

    static func exitDiagnostic(_ session: HIDSession, transport: ScalerTransport) async throws {
        let payload: [UInt8] = transport == .uart
            ? [0xA1, 0, 0] + Array("#nvtISP_MODE_OFF#".utf8) + [0x6A, 0x82]
            : [0xA1, 0, 0, 4, 0x34, 6, 0x3C]
        _ = try await session.exchange(MonitorProtocol.report(transport.reportID, payload), expectsReply: false)
        await session.close()
    }

    /// Reset may remove the USB service before output completion. A fresh bound
    /// service, followed by the caller's normal-mode verification, decides success.
    /// Only call after non-flashing diagnostics or fully verified programming.
    static func resetAndReacquire(_ session: HIDSession, previous: MonitorDevice, transport: ScalerTransport) async throws -> MonitorDevice {
        var submissionFailure: String?
        do { try await exitDiagnostic(session, transport: transport) }
        catch { submissionFailure = error.localizedDescription }
        await session.close()
        do {
            if transport == .uart {
                // UART exit resets the scaler; it need not remove the USB bridge.
                // The caller still verifies normal identity and preservation.
                guard submissionFailure == nil else {
                    throw UpdaterError("UART exit submission did not complete.")
                }
                try await Task.sleep(for: .seconds(30))
                return try matchingDevice(previous)
            }
            return try await reacquire(previous)
        }
        catch {
            throw UpdaterError("\(error.localizedDescription) Reset submission: \(submissionFailure ?? "completed").")
        }
    }

    static func matchingDevice(_ previous: MonitorDevice) throws -> MonitorDevice {
        let matches = try MonitorDevice.discover().filter { $0.serial == previous.serial && $0.location == previous.location }
        guard matches.count == 1, let device = matches.first else {
            throw UpdaterError("The original monitor is absent or ambiguous after ISP.")
        }
        return device
    }

    static func reacquire(_ previous: MonitorDevice) async throws -> MonitorDevice {
        let deadline = ContinuousClock.now + .seconds(45)
        while ContinuousClock.now < deadline {
            if let device = try? matchingDevice(previous), device.id != previous.id {
                // A fresh USB service is necessary but not sufficient for app
                // readiness. Allow the vendor's normal startup settling period.
                // Earlier diagnostics settled30s after removal. The bridge can
                // appear transiently before the scaler finishes rebooting.
                try await Task.sleep(for: .seconds(30))
                return try matchingDevice(device)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw UpdaterError("The monitor did not re-enumerate after ISP exit.")
    }
}

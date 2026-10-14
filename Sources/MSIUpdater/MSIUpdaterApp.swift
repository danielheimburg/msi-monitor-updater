import AppKit
import Darwin
import SwiftUI

@main
enum MSIUpdaterMain {
    private enum TransactionAction: String {
        case prepare = "--prepare"
        case update = "--update"
        case updateFW046 = "--update-fw046"
    }

    private enum Command {
        case inspectMonitor
        case inspectImage(URL)
        case plan(image: URL, snapshot: URL)
        case transaction(TransactionAction, image: URL, records: URL)

        init?(_ arguments: [String]) {
            switch (arguments.first, arguments.count) {
            case ("--inspect-monitor", 1): self = .inspectMonitor
            case ("--inspect-image", 2): self = .inspectImage(URL(fileURLWithPath: arguments[1]))
            case ("--plan", 3):
                self = .plan(image: URL(fileURLWithPath: arguments[1]), snapshot: URL(fileURLWithPath: arguments[2], isDirectory: true))
            case (let flag?, 3):
                guard let action = TransactionAction(rawValue: flag) else { return nil }
                self = .transaction(action, image: URL(fileURLWithPath: arguments[1]), records: URL(fileURLWithPath: arguments[2], isDirectory: true))
            default: return nil
            }
        }
    }

    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty {
            MSIUpdaterApp.main()
            return
        }
        guard let command = Command(arguments) else {
            writeCLIOutput("Usage: MSIUpdater [--inspect-image IMAGE | --inspect-monitor | --plan IMAGE SNAPSHOT_DIRECTORY | --prepare IMAGE RECORD_DIRECTORY | --update IMAGE RECORD_DIRECTORY | --update-fw046 IMAGE RECORD_DIRECTORY]\n")
            exit(2)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let result: Data
            switch command {
            case .inspectImage(let url):
                let image = try FirmwareImage(url: url)
                let modelCode = String(format: "%02X", image.profile.modelCode)
                let inspection: [String: Any] = [
                    "version": image.version,
                    "model": image.profile.modelName,
                    "modelCode": modelCode,
                    "sha256": image.sha256,
                    "byteLength": image.bytes.count,
                    "paddedByteLength": image.paddedLength,
                    "flashEligibleModel": true,
                    "backend": "Novatek / Nuvoton",
                    "internalTransport": image.profile.transport.name,
                    "requiredPanel": image.panel,
                    "panel": image.panel,
                    "sourceAuthenticityVerified": false,
                    "sameBranchRequired": true,
                    "bootCodeByteLength": image.profile.bootCodeLength,
                    "partitionTableInspected": true,
                    "hardwareValidation": "Previous build: MEG342C FW046 reinstallation only; this expansion is offline-validated",
                    "partitions": image.partitions.map { ["offset": $0.offset, "length": $0.length] }
                ]
                result = try JSONSerialization.data(withJSONObject: inspection, options: [.prettyPrinted, .sortedKeys])
            case .plan(let imageURL, let snapshot):
                let image = try FirmwareImage(url: imageURL)
                result = try encoder.encode(offlinePlan(image: image, snapshot: snapshot))
            case .inspectMonitor:
                result = try encoder.encode(await MonitorProtocol.inspect(connectedDevice()))
            case .transaction(let action, let imageURL, let records):
                // File/alias validation must still precede USB discovery.
                let image = try FirmwareImage(url: imageURL)
                if action == .updateFW046, image.version != "046" || image.profile.modelCode != 0x90 {
                    throw UpdaterError("--update-fw046 accepts only MEG342C FW046. Use --update for other compatible images.")
                }
                let device = try connectedDevice()
                switch action {
                case .prepare:
                    result = try encoder.encode(await UpdatePreparation.run(image: image, device: device, parent: records))
                case .update, .updateFW046:
                    let update = try await FirmwareUpdate.run(image: image, device: device, parent: records) { message in
                        writeCLIOutput(message.message + "\n")
                    }
                    result = try encoder.encode(update)
                }
            }
            guard writeCLIOutput(String(decoding: result, as: UTF8.self) + "\n", to: .standardOutput) else {
                writeCLIOutput("Could not write the result to stdout. For an update, check the saved transaction record for its outcome.\n")
                exit(1)
            }
        } catch {
            var message = error.localizedDescription
            if let failure = error as? UpdateRecord.Failure { message += " Record: \(failure.recordDirectory.path)" }
            writeCLIOutput(message + "\n")
            exit(1)
        }
    }

    /// Console failures must not interrupt a firmware transaction. Suppress SIGPIPE
    /// on this descriptor and use the throwing API instead of Objective-C exceptions.
    @discardableResult
    private static func writeCLIOutput(_ message: String, to handle: FileHandle = .standardError) -> Bool {
        guard fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { return false }
        do {
            try handle.write(contentsOf: Data(message.utf8))
            return true
        } catch {
            return false
        }
    }

    private static func connectedDevice() throws -> MonitorDevice {
        let devices = try MonitorDevice.discover()
        guard devices.count == 1, let device = devices.first else {
            throw UpdaterError("Connect exactly one supported monitor to macOS.")
        }
        return device
    }

    /// An offline snapshot is diagnostic input only. Live updates acquire fresh state.
    private static func offlinePlan(image: FirmwareImage, snapshot: URL) throws -> UpdatePlan {
        let information = try JSONDecoder().decode(MonitorInformation.self,
            from: Data(contentsOf: snapshot.appendingPathComponent("monitor.json")))
        guard information.model == image.profile.modelCode else {
            throw UpdaterError("The snapshot belongs to a different monitor model.")
        }
        try image.requireCompatible(with: information)
        let hardwareURL = snapshot.appendingPathComponent("hardware.json")
        let hardware: ScalerHardware
        if FileManager.default.fileExists(atPath: hardwareURL.path) {
            hardware = try JSONDecoder().decode(ScalerHardware.self, from: Data(contentsOf: hardwareURL))
            try hardware.validate()
        } else if information.model == 0x90 {
            // Historical MEG snapshots precede this separate hardware record.
            hardware = ScalerHardware(scalerID: 0xA500, flashID: [0xC8, 0x40, 0x19])
        } else {
            throw UpdaterError("This snapshot needs a verified hardware.json identity record.")
        }
        func readRange(address: Int, count: Int) throws -> [UInt8] {
            let url = snapshot.appendingPathComponent(String(format: "physical-%08X.bin", address))
            let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard properties.isRegularFile == true, properties.fileSize == count else {
                throw UpdaterError("The snapshot range \(url.lastPathComponent) has an invalid size.")
            }
            return Array(try Data(contentsOf: url))
        }
        var metadata: [Int: [UInt8]] = [:]
        for address in UpdatePlan.metadataAddresses(capacity: hardware.capacity) {
            metadata[address] = try readRange(address: address, count: FirmwareImage.blockSize)
        }
        var loaders: [Int: [UInt8]] = [:]
        for address in UpdatePlan.bootCodeAddresses(capacity: hardware.capacity) {
            loaders[address] = try readRange(address: address, count: image.profile.bootCodeLength)
        }
        return try UpdatePlan(image: image, installedVersion: information.version,
            metadataSectors: metadata, bootCodeCopies: loaders, flashCapacity: hardware.capacity)
    }
}

struct MSIUpdaterApp: App {
    @NSApplicationDelegateAdaptor(UpdaterApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("MSI Firmware Updater", id: "updater") {
            UpdaterView()
                .frame(minWidth: 860, minHeight: 800)
        }
        .defaultSize(width: 940, height: 840)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class UpdaterApplicationDelegate: NSObject, NSApplicationDelegate {
    static var updateInProgress = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.updateInProgress ? .terminateCancel : .terminateNow
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            FileHandle.standardError.write(Data("Usage: MSIUpdater [--inspect-image IMAGE | --inspect-monitor | --plan IMAGE SNAPSHOT_DIRECTORY | --prepare IMAGE RECORD_DIRECTORY | --update IMAGE RECORD_DIRECTORY | --update-fw046 IMAGE RECORD_DIRECTORY]\n".utf8))
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
                        FileHandle.standardError.write(Data((message.message + "\n").utf8))
                    }
                    result = try encoder.encode(update)
                }
            }
            print(String(decoding: result, as: UTF8.self))
        } catch {
            var message = error.localizedDescription
            if let failure = error as? UpdateRecord.Failure { message += " Record: \(failure.recordDirectory.path)" }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
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
                .frame(minWidth: 560, minHeight: 430)
        }
        .defaultSize(width: 640, height: 520)
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

@MainActor
struct UpdaterView: View {
    @State private var devices: [MonitorDevice] = []
    @State private var image: FirmwareImage?
    @State private var error: String?
    @State private var choosingImage = false
    @State private var inspecting = false
    @State private var information: MonitorInformation?
    @State private var recordsDirectory: URL?
    @State private var confirmingUpdate = false
    @State private var updating = false
    @State private var progress: FirmwareUpdate.Progress?
    @State private var showingHelp = false
    @State private var completedRecord: URL?

    private var compatibilityIssue: String? {
        guard let image else { return nil }
        guard let information else { return "Read monitor information to check the installed release." }
        do {
            try image.requireCompatible(with: information)
            return nil
        } catch { return error.localizedDescription }
    }

    private var downgradeWarning: String? {
        guard let image, let information else { return nil }
        return image.downgradeWarning(installedVersion: information.version)
    }

    private var confirmationTitle: String {
        guard let image else { return "Update this monitor?" }
        let action = downgradeWarning == nil ? "Update" : "Downgrade"
        return "\(action) this monitor to FW\(image.version)?"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MSI Firmware Updater").font(.title)
                HStack {
                    Text("MSI scaler firmware · Preview").foregroundStyle(.secondary)
                    Spacer()
                    Button { showingHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain)
                        .help("Compatibility, update requirements and privacy")
                        .accessibilityLabel("Update help")
                }

                GroupBox("Monitor") {
                    VStack(alignment: .leading, spacing: 8) {
                        if devices.isEmpty {
                            Text("No compatible MSI controller found. Connect the monitor’s USB data cable.")
                        }
                        ForEach(devices) { device in
                            Text(device.product)
                            Text("USB controller connected").font(.caption).foregroundStyle(.secondary)
                        }
                        if devices.count > 1 {
                            Text("Connect only the monitor you intend to update.").foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Refresh") { refresh() }.disabled(inspecting || updating)
                            Button("Read monitor information") { Task { await inspect() } }
                                .disabled(inspecting || updating || devices.count != 1)
                            if inspecting { ProgressView().controlSize(.small) }
                        }
                        if let information {
                            Text("\(FirmwareImage.modelProfiles.first(where: { $0.modelCode == information.model })?.modelName ?? "MSI monitor") · FW\(information.version) · preservation checksums verified")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Firmware") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let image {
                            Text("\(image.profile.modelName) · FW\(image.version)")
                            Text(image.url.lastPathComponent).textSelection(.enabled)
                            Text("Firmware structure validated · \(image.bytes.count.formatted()) bytes")
                                .font(.caption).foregroundStyle(.secondary)
                            LabeledContent("Update method", value: "Novatek / Nuvoton")
                                .font(.caption)
                            LabeledContent("Internal connection", value: image.profile.transport.displayName)
                                .font(.caption)
                            LabeledContent("Panel", value: image.panel).font(.caption)
                            Text("\(image.partitions.count) partitions · bounds and overlap checks passed")
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Image checksum") {
                                Text(image.sha256).font(.caption.monospaced()).textSelection(.enabled)
                            }
                            if let issue = compatibilityIssue {
                                Text(issue).font(.caption).foregroundStyle(.orange)
                            } else if let information {
                                Text("FW\(information.version) → FW\(image.version). Flash identity and installed metadata are checked again before writing.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let downgradeWarning {
                                Text(downgradeWarning).font(.callout).foregroundStyle(.orange)
                            }
                            Text("Only MEG 342C FW046 reinstalls have been hardware-tested by this project.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Choose firmware for this monitor. Model, version, panel and layout are read from the file.")
                        }
                        Button("Choose firmware…") { choosingImage = true }.disabled(updating)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                Text("Downgrades show a warning before confirmation. Keep power and USB connected. The display will go blank and restart. Recovery after an interrupted or damaged update is unverified.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Choose backup folder…") { chooseRecordsDirectory() }.disabled(updating || inspecting)
                    if let recordsDirectory { Text(recordsDirectory.lastPathComponent).font(.caption) }
                    Spacer()
                    Button(image.map { "Update to FW\($0.version)…" } ?? "Update…") { confirmingUpdate = true }
                        .disabled(updating || inspecting || devices.count != 1 || image == nil || information == nil || compatibilityIssue != nil || recordsDirectory == nil)
                }
                if let progress {
                    VStack(alignment: .leading, spacing: 8) {
                        if case .programming(let completed, let total) = progress {
                            ProgressView(value: Double(completed), total: Double(total))
                                .accessibilityLabel("Firmware writing and verification")
                                .accessibilityValue("\(Int(Double(completed) / Double(total) * 100)) percent")
                            HStack {
                                Text(progress.message)
                                Spacer()
                                Text("\(Int(Double(completed) / Double(total) * 100))%")
                                    .monospacedDigit()
                            }
                        } else {
                            HStack {
                                if updating { ProgressView().controlSize(.small) }
                                Text(progress.message)
                            }
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                }
                if let completedRecord {
                    Button("Show update record") { NSWorkspace.shared.activateFileViewerSelecting([completedRecord]) }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .task { refresh() }
        .sheet(isPresented: $showingHelp) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you update").font(.title2).fontWeight(.semibold)
                Text("Firmware is inspected for model, version, panel, structure and supported bootloader. Whole-file hashes do not restrict releases or authenticate their origin. Obtain firmware from MSI.")
                Text("Version transitions, including downgrades, have not been hardware-tested. A downgrade warning requires confirmation in this window. Hardware branches and required panels cannot be crossed. Only MEG 342C FW046 reinstalls have been tested by this project.")
                Text("Use a reliable USB data cable directly to the Mac. Release Windows VM passthrough and close other monitor-control applications.")
                Text("Keep the Mac and monitor powered and connected. The display will go blank and reconnect during the final restart. A full progress bar finishes writing; the app still verifies and restores your monitor afterward.")
                Text("Backup records contain device-specific calibration, serial data and USB traffic. Keep them private. If the update stops, preserve the record and keep the monitor connected; automatic resume and damaged-firmware recovery are unavailable.")
                Text("Independent utility. This app is not developed or endorsed by MSI.")
                    .foregroundStyle(.secondary)
                HStack {
                    Link("Official firmware", destination: URL(string: "https://www.msi.com/support")!)
                    Spacer()
                    Button("Done") { showingHelp = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 520)
        }
        .alert(confirmationTitle, isPresented: $confirmingUpdate) {
            Button("Cancel", role: .cancel) {}
            Button(downgradeWarning == nil ? "Update" : "Downgrade") { Task { await update() } }
        } message: {
            Text((downgradeWarning.map { $0 + "\n\n" } ?? "")
                + "This writes the selected firmware. Keep this Mac and monitor powered and connected until verification finishes. Do not force quit; interrupted-update recovery is not verified.")
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [UTType(filenameExtension: "bin", conformingTo: .data)!]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                image = try FirmwareImage(url: url)
                error = nil
            } catch {
                image = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func refresh() {
        information = nil
        do {
            devices = try MonitorDevice.discover()
            error = nil
        } catch {
            devices = []
            self.error = error.localizedDescription
        }
    }

    private func inspect() async {
        guard devices.count == 1, let device = devices.first else { return }
        inspecting = true
        information = nil
        defer { inspecting = false }
        do {
            information = try await MonitorProtocol.inspect(device)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chooseRecordsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use backup folder"
        if panel.runModal() == .OK { recordsDirectory = panel.url }
    }

    private func update() async {
        guard !updating, !UpdaterApplicationDelegate.updateInProgress,
              devices.count == 1, let device = devices.first,
              let image, let information, compatibilityIssue == nil,
              let recordsDirectory else { return }
        updating = true
        UpdaterApplicationDelegate.updateInProgress = true
        error = nil
        completedRecord = nil
        progress = nil
        defer {
            updating = false
            UpdaterApplicationDelegate.updateInProgress = false
        }
        do {
            let result = try await FirmwareUpdate.run(image: image, device: device, parent: recordsDirectory, confirmedVersion: information.version) { message in
                await MainActor.run { progress = message }
            }
            devices = [result.device]
            self.information = result.information
            completedRecord = result.recordDirectory
        } catch {
            progress = nil
            completedRecord = (error as? UpdateRecord.Failure)?.recordDirectory
            self.error = "Update stopped. \(error.localizedDescription)"
        }
    }
}

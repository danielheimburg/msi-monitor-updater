import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
enum MSIUpdaterMain {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--inspect-monitor"] || (arguments.count == 3 && ["--prepare", "--update-fw046"].contains(arguments[0])) {
            do {
                let devices = try MonitorDevice.discover()
                guard devices.count == 1, let device = devices.first else {
                    throw UpdaterError("Connect exactly one supported monitor to macOS.")
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let result: Data
                if arguments[0] == "--update-fw046" {
                    let image = try FirmwareImage(url: URL(fileURLWithPath: arguments[1]))
                    let update = try await FirmwareUpdate.run(image: image, device: device,
                        parent: URL(fileURLWithPath: arguments[2], isDirectory: true)) { message in
                            FileHandle.standardError.write(Data((message.message + "\n").utf8))
                        }
                    result = try encoder.encode(update)
                } else if arguments[0] == "--prepare" {
                    let image = try FirmwareImage(url: URL(fileURLWithPath: arguments[1]))
                    let preparation = try await UpdatePreparation.run(image: image, device: device,
                        parent: URL(fileURLWithPath: arguments[2], isDirectory: true))
                    result = try encoder.encode(preparation)
                } else {
                    result = try encoder.encode(await MonitorProtocol.inspect(device))
                }
                print(String(decoding: result, as: UTF8.self))
            } catch {
                var message = error.localizedDescription
                if let failure = error as? FirmwareUpdate.Failure { message += " Record: \(failure.recordDirectory.path)" }
                FileHandle.standardError.write(Data((message + "\n").utf8))
                exit(1)
            }
        } else if CommandLine.arguments.count == 1 {
            MSIUpdaterApp.main()
        } else {
            FileHandle.standardError.write(Data("Usage: MSIUpdater [--inspect-monitor | --prepare IMAGE RECORD_DIRECTORY | --update-fw046 IMAGE RECORD_DIRECTORY]\n".utf8))
            exit(2)
        }
    }
}

struct MSIUpdaterApp: App {
    @NSApplicationDelegateAdaptor(UpdaterApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("MSI Firmware Updater", id: "updater") {
            UpdaterView()
                .frame(minWidth: 560, minHeight: 430)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MSI Firmware Updater").font(.title)
            HStack {
                Text("MEG 342C QD-OLED · Preview").foregroundStyle(.secondary)
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
                        Text("MEG342C · FW\(information.version) · calibration and serial checksums verified")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Firmware") {
                VStack(alignment: .leading, spacing: 8) {
                    if let image {
                        Text("Reviewed official firmware: FW\(image.version)")
                        Text(image.url.lastPathComponent).textSelection(.enabled)
                        Text("Official image verified · \(image.bytes.count.formatted()) bytes")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose the reviewed MEG342C FW046 image.")
                    }
                    Button("Choose firmware…") { choosingImage = true }.disabled(updating)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text("Keep power and USB connected. The display will go blank and restart. Recovery after an interrupted or damaged update is unverified.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Choose backup folder…") { chooseRecordsDirectory() }.disabled(updating || inspecting)
                if let recordsDirectory { Text(recordsDirectory.lastPathComponent).font(.caption) }
                Spacer()
                Button("Update to FW046…") { confirmingUpdate = true }
                    .disabled(updating || inspecting || devices.count != 1 || image == nil || recordsDirectory == nil)
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
        .task { refresh() }
        .sheet(isPresented: $showingHelp) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before you update").font(.title2).fontWeight(.semibold)
                Text("Supported: MSI MEG 342C QD-OLED with the reviewed official FW046 image. Other models and modified images are unsupported.")
                Text("Use a reliable USB data cable directly to the Mac. Release Windows VM passthrough and close other monitor-control applications.")
                Text("Keep the Mac and monitor powered and connected. The display will go blank and reconnect during the final restart. A full progress bar finishes writing; the app still verifies and restores your monitor afterward.")
                Text("Backup records contain device-specific calibration, serial data and USB traffic. Keep them private. If the update stops, preserve the record and keep the monitor connected; automatic resume and damaged-firmware recovery are unavailable.")
                Text("Independent utility. This app is not developed or endorsed by MSI.")
                    .foregroundStyle(.secondary)
                HStack {
                    Link("Official firmware", destination: URL(string: "https://www.msi.com/Monitor/MEG-342C-QD-OLED/support#firmware")!)
                    Spacer()
                    Button("Done") { showingHelp = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 520)
        }
        .alert("Update this monitor to FW046?", isPresented: $confirmingUpdate) {
            Button("Cancel", role: .cancel) {}
            Button("Update") { Task { await update() } }
        } message: {
            Text("This writes the reviewed official image. Keep this Mac and monitor powered and connected until verification finishes. Do not force quit; interrupted-update recovery is not verified.")
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.data]) { result in
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
              let image, let recordsDirectory else { return }
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
            let result = try await FirmwareUpdate.run(image: image, device: device, parent: recordsDirectory) { message in
                await MainActor.run { progress = message }
            }
            information = result.information
            completedRecord = result.recordDirectory
        } catch {
            progress = nil
            completedRecord = (error as? FirmwareUpdate.Failure)?.recordDirectory
            self.error = "Update stopped. \(error.localizedDescription)"
        }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct UpdaterView: View {
    private enum Workspace: String, CaseIterable {
        case update = "Update"
        case image = "Image details"
        case activity = "Activity"
        case help = "Help"
    }

    private enum HelpTopic: String, CaseIterable {
        case compatibility = "Compatibility"
        case connection = "Connection & restart"
        case records = "Records & recovery"
    }

    private enum Outcome {
        case complete(FirmwareUpdate)
        case stopped(String, URL?)

        var record: URL? {
            switch self {
            case .complete(let result): result.recordDirectory
            case .stopped(_, let record): record
            }
        }

        var stopped: Bool {
            if case .stopped = self { return true }
            return false
        }
    }

    @State private var devices: [MonitorDevice] = []
    @State private var information: MonitorInformation?
    @State private var image: FirmwareImage?
    @State private var recordsDirectory: URL?
    @State private var error: String?
    @State private var inspecting = false
    @State private var updating = false
    @State private var confirmingUpdate = false
    @State private var progress: FirmwareUpdate.Progress?
    @State private var outcome: Outcome?
    @State private var workspace: Workspace = .update
    @State private var helpTopic: HelpTopic = .compatibility

    private var compatibilityIssue: String? {
        guard let image, let information else { return nil }
        do {
            try image.requireCompatible(with: information)
            return nil
        } catch { return error.localizedDescription }
    }

    private var downgradeWarning: String? {
        guard let image, let information else { return nil }
        return image.downgradeWarning(installedVersion: information.version)
    }

    private var action: String {
        guard let image else { return "Update firmware" }
        if image.version == information?.version { return "Reinstall FW\(image.version)" }
        return "\(downgradeWarning == nil ? "Update to" : "Downgrade to") FW\(image.version)"
    }

    private var readiness: String {
        if updating { return progress?.message ?? "Starting update" }
        if outcome?.stopped == true { return "Update stopped. Preserve the record before taking further action." }
        if inspecting { return "Reading identity and preservation data…" }
        if devices.count != 1 { return "Connect exactly one supported MSI controller." }
        if information == nil { return "Read the monitor identity to continue." }
        if image == nil { return "Choose an official .bin firmware image." }
        if let issue = compatibilityIssue { return issue }
        if recordsDirectory == nil { return "Choose a private folder for backups and the update record." }
        return "Ready to review. Hardware and installed layout are checked again before writing."
    }

    private var canUpdate: Bool {
        !updating && !inspecting && outcome?.stopped != true && devices.count == 1
            && information != nil && image != nil && compatibilityIssue == nil && recordsDirectory != nil
    }

    private var phase: Int? {
        guard let progress else { return nil }
        switch progress {
        case .preparing: return 0
        case .programming: return 1
        case .verifying: return 2
        case .restarting: return 3
        case .restoring: return 4
        case .complete: return 5
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmingUpdate ? "Review firmware write" : "MSI Firmware Updater")
                        .font(.title2).fontWeight(.semibold)
                    Text("Preview · Independent macOS utility")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !confirmingUpdate {
                    Button { workspace = .help } label: { Label("Help", systemImage: "questionmark.circle") }
                }
            }
            .padding(24)

            Divider()
            Group {
                if confirmingUpdate {
                    confirmation
                } else {
                    TabView(selection: $workspace) {
                        updateWorkspace.tabItem { Text(Workspace.update.rawValue) }.tag(Workspace.update)
                        imageDetails.tabItem { Text(Workspace.image.rawValue) }.tag(Workspace.image)
                        activity.tabItem { Text(Workspace.activity.rawValue) }.tag(Workspace.activity)
                        help.tabItem { Text(Workspace.help.rawValue) }.tag(Workspace.help)
                    }
                }
            }
            .frame(maxWidth: 1080, maxHeight: .infinity, alignment: .top)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            footer
                .padding(20)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { refresh() }
    }

    private var updateWorkspace: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installed monitor").font(.headline)
                        Text(information.map { info in
                            FirmwareImage.modelProfiles.first(where: { $0.modelCode == info.model })?.modelName ?? "MSI monitor"
                        } ?? devices.first?.product ?? "No monitor connected")
                            .font(.title3).fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(information.map { "FW\($0.version)" } ?? "Identity not read")
                            .font(.title2.monospacedDigit())
                        if let information {
                            fact("Model code", String(format: "0x%02X", information.model))
                            fact("Panel", information.panel ?? "Unavailable")
                            Label("Preservation checksums verified", systemImage: "checkmark.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Read model, version, panel and preservation data from the connected controller.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let device = devices.first {
                            fact("USB", "1462:3FA4")
                            fact("Location", String(format: "0x%08X", device.location))
                        }
                        HStack {
                            Button("Refresh") { refresh() }.disabled(inspecting || updating || outcome?.stopped == true)
                            Button("Read identity") { Task { await inspect() } }
                                .disabled(inspecting || updating || devices.count != 1 || outcome?.stopped == true)
                            if inspecting { ProgressView().controlSize(.small) }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected firmware").font(.headline)
                        Text(image?.profile.modelName ?? "Choose a firmware image")
                            .font(.title3).fontWeight(.medium)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(image.map { "FW\($0.version)" } ?? "No file selected")
                            .font(.title2.monospacedDigit())
                        if let image {
                            fact("Internal link", image.profile.transport.displayName)
                            fact("Panel", image.panel)
                            Text(image.url.lastPathComponent)
                                .font(.callout).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(image.bytes.count.formatted()) bytes · \(image.partitions.count) partitions")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Inspect image details") { workspace = .image }
                        } else {
                            Text("Model, version, panel and layout are parsed from the file. Obtain firmware from MSI.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(image == nil ? "Choose firmware…" : "Change firmware…") { chooseFirmware() }
                            .disabled(updating || inspecting || outcome?.stopped == true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Backups & update record").font(.headline)
                    Spacer()
                    Button(recordsDirectory == nil ? "Choose folder…" : "Change folder…") { chooseRecordsDirectory() }
                        .disabled(updating || inspecting || outcome?.stopped == true)
                }
                Text(recordsDirectory?.path ?? "Choose an existing private folder. Each update creates its own protected transaction directory.")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error { notice("Cannot continue", error, symbol: "exclamationmark.triangle", color: .red) }
            if let issue = compatibilityIssue { notice("Image does not match", issue, symbol: "exclamationmark.triangle", color: .orange) }
            if let downgradeWarning { notice("Downgrade selected", downgradeWarning, symbol: "exclamationmark.triangle", color: .orange) }
            Text("Only MEG 342C FW046 reinstalls have been hardware-tested. Other models and version transitions remain untested on hardware. Recovery after interruption or damaged firmware is unavailable.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var imageDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let image {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(image.profile.modelName) · FW\(image.version)").font(.headline)
                        Text(image.url.lastPathComponent).font(.callout).textSelection(.enabled)
                    }
                    Spacer()
                    Label("Structure validated", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("Panel").foregroundStyle(.secondary); Text(image.panel) }
                    GridRow { Text("Programming family").foregroundStyle(.secondary); Text("Novatek / Nuvoton · \(image.profile.transport.displayName)") }
                    GridRow { Text("File / padded size").foregroundStyle(.secondary); Text("\(image.bytes.count.formatted()) / \(image.paddedLength.formatted()) bytes") }
                }.font(.callout).textSelection(.enabled)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 6) {
                    GridRow {
                        Text("Partition"); Text("Image offset"); Text("Length (bytes)")
                    }.fontWeight(.medium)
                    ForEach(Array(image.partitions.enumerated()), id: \.offset) { index, partition in
                        GridRow {
                            Text("\(index + 1)")
                            Text(String(format: "0x%08X", partition.offset))
                            Text(partition.length.formatted())
                        }.monospacedDigit()
                    }
                }.font(.callout).textSelection(.enabled)
                Text("All partition bounds, alignment and overlap checks passed.").font(.callout).foregroundStyle(.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image SHA-256").font(.callout).fontWeight(.medium)
                    Text(image.sha256).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text("Bootloader SHA-256").font(.callout).fontWeight(.medium)
                    Text(image.loaderDigest).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
                Text("The image hash identifies this file; it does not authenticate MSI origin or restrict releases. Bootloader identity is checked against the supported programming contract.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No image to inspect").font(.headline)
                Text("Choose a .bin file in Update to inspect its identity, partition layout and checksums.")
                    .foregroundStyle(.secondary)
                Button("Choose firmware…") { chooseFirmware() }.disabled(updating || inspecting || outcome?.stopped == true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(outcome?.stopped == true ? "Update stopped" : phase == 5 ? "Update verified" : updating ? "Update in progress" : "No update running")
                .font(.title3).fontWeight(.semibold)
            ForEach(Array(["Preserve", "Write", "Verify", "Restart", "Restore"].enumerated()), id: \.offset) { index, title in
                HStack(spacing: 12) {
                    Image(systemName: phase.map { $0 > index ? "checkmark.circle.fill" : $0 == index ? "circle.inset.filled" : "circle" } ?? "circle")
                        .foregroundStyle(phase == index ? Color.accentColor : Color.secondary)
                    Text(title).fontWeight(phase == index ? .semibold : .regular)
                    Spacer()
                    Text(phase.map { $0 > index ? "Verified" : $0 == index ? (outcome?.stopped == true ? "Stopped" : "In progress") : "Pending" } ?? "Not started")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if case .programming(let completed, let total) = progress {
                ProgressView(value: Double(completed), total: Double(total))
                    .accessibilityLabel("Writing phase")
                    .accessibilityValue("\(Int(Double(completed) / Double(total) * 100)) percent")
                Text("\(completed) of \(total) write operations verified · \(Int(Double(completed) / Double(total) * 100))%")
                    .monospacedDigit().font(.callout)
            } else {
                Text(progress?.message ?? "The app saves preservation data, writes and verifies the image, restarts the monitor, then restores and verifies calibration and serial data.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if case .stopped(let message, _) = outcome {
                notice("Preserve the stopped state", message, symbol: "exclamationmark.triangle", color: .red)
                Text("Keep the monitor connected. Do not treat another update attempt as a resume. Automatic recovery and rollback are unavailable.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            } else if case .complete = outcome {
                Label("Firmware, calibration and serial data verified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Keep power and USB connected. The display goes blank during restart. 100% writing is followed by final verification and preservation restoration.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let record = outcome?.record {
                Text(record.path).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Show update record") { NSWorkspace.shared.activateFileViewerSelecting([record]) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Help topic", selection: $helpTopic) {
                ForEach(HelpTopic.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            switch helpTopic {
            case .compatibility:
                helpSection("What the app checks", "Firmware identity comes from its model, version and panel records. Size, partition geometry, padding and supported bootloader are validated. Installed metadata and hardware identity are checked independently before writing.")
                helpSection("What has been tested", "This project has hardware-tested only MEG 342C FW046 reinstalls over USB-C. Additional model profiles are inferred from firmware and Windows-backend analysis. Version transitions, including downgrades, remain untested on hardware. Hardware branches and required panels cannot be crossed.")
                helpSection("Use official firmware", "Whole-file hashes do not restrict releases or authenticate origin. Obtain the image separately from MSI. This independent utility is not developed or endorsed by MSI.")
                Link("Open MSI support", destination: URL(string: "https://www.msi.com/support")!)
            case .connection:
                helpSection("Before writing", "Use a reliable USB data cable directly to the Mac. Release Windows VM passthrough and close other monitor-control apps. Connect one supported MSI controller. Keep the Mac and monitor powered throughout the operation.")
                helpSection("During restart", "The display goes blank and USB can disconnect during the intended final reset. The app waits for the matching monitor, checks firmware identity, restores preservation data and verifies it. A full writing bar or the monitor reappearing is not completion.")
                helpSection("Let verification finish", "There is no cancel action after the update starts. Normal application quit is blocked until the operation returns. Forced termination, power loss and cable removal can interrupt the transaction; the quit guard cannot prevent them.")
            case .records:
                helpSection("Keep records private", "Every update creates an owner-only transaction directory with device identity, calibration and serial backups, boot and metadata ranges, the plan and raw USB exchanges. These records contain device-specific information. No telemetry or upload feature is provided.")
                helpSection("If an update stops", "Preserve the complete record and keep the monitor powered and connected. An uncertain command is not automatically replayed. Restarting the app or rerunning an update is not a resume procedure.")
                helpSection("Recovery boundary", "Records are evidence, not an executable recovery plan or complete flash backup. Automatic continuation, rollback and damaged-firmware recovery are unavailable. Dual banks do not establish a recovery guarantee.")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(action).font(.title2).fontWeight(.semibold)
            if let image, let information {
                fact("Monitor", image.profile.modelName)
                fact("Installed → selected", "FW\(information.version) → FW\(image.version)")
                fact("Panel", image.panel)
                Text(image.url.lastPathComponent).font(.callout).textSelection(.enabled)
                Text("Record destination: \(recordsDirectory?.path ?? "Not selected")")
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if let downgradeWarning {
                notice("Downgrade warning", downgradeWarning, symbol: "exclamationmark.triangle", color: .orange)
            }
            helpSection("This writes firmware to the monitor", "Keep this Mac and the monitor powered and USB connected until verification finishes. The display will go blank and restart. Do not force quit. Interrupted-update and damaged-firmware recovery are unavailable.")
            helpSection("Completion includes preservation", "A full writing bar is followed by final checks, restart and restoration. The app reports success only after fresh firmware, calibration and serial verification.")
            Text("Only MEG 342C FW046 reinstalls have been hardware-tested. Other model profiles and version transitions remain untested on hardware.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                if confirmingUpdate {
                    Text("Confirm only when power and USB can remain connected.")
                } else {
                    Text(updating && workspace == .activity ? "Keep power and USB connected until final verification completes." : readiness)
                    if updating && workspace != .activity {
                        Button("Show activity") { workspace = .activity }.buttonStyle(.link)
                    }
                }
            }
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if confirmingUpdate {
                Button("Cancel") { confirmingUpdate = false }.keyboardShortcut(.cancelAction)
                Button(action) { Task { await update() } }.buttonStyle(.borderedProminent)
            } else {
                Button("\(action)…") { confirmingUpdate = true }
                    .buttonStyle(.borderedProminent).disabled(!canUpdate)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.font(.callout)
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notice(_ title: String, _ text: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.callout).fontWeight(.semibold).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
        } catch { self.error = error.localizedDescription }
    }

    private func chooseFirmware() {
        let panel = NSOpenPanel()
        panel.title = "Choose MSI firmware"
        panel.allowedContentTypes = [UTType(filenameExtension: "bin", conformingTo: .data)!]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.pathExtension.lowercased() == "bin" else {
                throw UpdaterError("Choose a .bin firmware file. Other file types are not accepted.")
            }
            image = try FirmwareImage(url: url)
            error = nil
        } catch {
            image = nil
            self.error = error.localizedDescription
            workspace = .update
        }
    }

    private func chooseRecordsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use record folder"
        if panel.runModal() == .OK { recordsDirectory = panel.url }
    }

    private func update() async {
        guard canUpdate, !UpdaterApplicationDelegate.updateInProgress,
              let device = devices.first, let image, let information, let recordsDirectory else { return }
        updating = true
        confirmingUpdate = false
        UpdaterApplicationDelegate.updateInProgress = true
        error = nil
        outcome = nil
        progress = nil
        workspace = .activity
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
            outcome = .complete(result)
        } catch {
            outcome = .stopped(error.localizedDescription, (error as? UpdateRecord.Failure)?.recordDirectory)
        }
    }
}

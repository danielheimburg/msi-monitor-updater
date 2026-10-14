import Foundation

/// An explicit public-field allowlist, independent of private transaction records.
/// Never encode MonitorInformation, UpdateRecord, error descriptions or file URLs here.
struct DiagnosticReport: Encodable, Sendable {
    let schema = 1
    var synthetic = false
    let id: String
    let appVersion: String
    let osVersion: String
    let modelCode: UInt8
    let panel: String
    let sourceVersion: String
    let targetVersion: String
    let transport: String
    let imageSHA256: String
    let imageBytes: Int
    let partitionCount: Int
    var phase = "preparing"
    var completedOperations = 0
    var totalOperations = 0
    var outcome = "stopped"
    var durationSeconds = 0

    init(image: FirmwareImage, installedVersion: String?) {
        id = UUID().uuidString.lowercased()
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        modelCode = image.profile.modelCode
        panel = image.panel
        sourceVersion = installedVersion ?? "unknown"
        targetVersion = image.version
        transport = image.profile.transport.name
        imageSHA256 = image.sha256
        imageBytes = image.bytes.count
        partitionCount = image.partitions.count
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Only observes progress supplied by the writer. It never reads the monitor or
/// the private journal, and has no networking or storage work during a transaction.
actor UpdateDiagnostics {
    private var report: DiagnosticReport
    private let started = ContinuousClock.now

    init(image: FirmwareImage, installedVersion: String? = nil) {
        report = DiagnosticReport(image: image, installedVersion: installedVersion)
    }

    func observe(_ progress: FirmwareUpdate.Progress) {
        switch progress {
        case .preparing: report.phase = "preparing"
        case .programming(let completed, let total):
            report.phase = "programming"
            report.completedOperations = completed
            report.totalOperations = total
        case .verifying: report.phase = "verifying"
        case .restarting: report.phase = "restarting"
        case .restoring: report.phase = "restoring"
        case .complete: report.phase = "complete"
        }
    }

    func finish(verified: Bool) -> DiagnosticReport {
        report.outcome = verified ? "verified" : "stopped"
        report.durationSeconds = Int(started.duration(to: .now).components.seconds)
        return report
    }
}

enum DiagnosticSubmission {
    static let preferenceKey = "submitRedactedDiagnostics"
    static let endpoint = URL(string: "https://msi-updater-reports.daniel-heimburg.workers.dev/v1/reports")!
    static let privacyURL = URL(string: "https://github.com/danielheimburg/msi-monitor-updater/blob/main/docs/app/diagnostics.md")!

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// Called after FirmwareUpdate.run has returned and closed its HID sessions.
    /// An upload result never changes the firmware result. No application retries,
    /// persistent queue, background session or automatic historical uploads.
    static func submit(_ report: DiagnosticReport, enabled: Bool) async -> String {
        guard enabled else { return "Not sent — diagnostic submission is off." }
        guard let data = try? report.data(), data.count <= 8192 else {
            return "Not sent — report could not be encoded."
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: ReportConnectionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 201 else {
                return "Delivery unconfirmed — no acceptance receipt. The firmware outcome is unchanged."
            }
            var reply = Data()
            for try await byte in bytes {
                guard reply.count < 1024 else { return "Receipt invalid — delivery is unconfirmed." }
                reply.append(byte)
            }
            struct Receipt: Decodable {
                let receipt: String
                let reference: String
            }
            let receipt = try JSONDecoder().decode(Receipt.self, from: reply)
            guard receipt.receipt == report.id,
                  receipt.reference.range(of: #"^reports/\d{4}-\d{2}-\d{2}/\d{1,4}\.json$"#,
                                          options: .regularExpression) != nil else {
                return "Receipt invalid — delivery is unconfirmed."
            }
            return "Redacted report received. Reference: \(receipt.reference) · ID: \(report.id)"
        } catch {
            return "Delivery unconfirmed — no retry. The firmware outcome is unchanged."
        }
    }
}

private final class ReportConnectionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

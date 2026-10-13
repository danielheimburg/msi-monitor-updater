import Foundation
import Darwin

/// Owner-only evidence for one device transaction. The append-only journal is the
/// source of phase history; it never authorizes retry or crash-resume.
final class UpdateRecord: @unchecked Sendable {
    struct Event: Codable {
        let time: Date
        let elapsedNanoseconds: UInt64
        let operation: String
        let detail: String?
        let report: [UInt8]?
        let result: Int32?
    }

    let directory: URL
    private let lock = NSLock()
    private let journal: FileHandle
    private let encoder: JSONEncoder
    private let started = DispatchTime.now().uptimeNanoseconds

    init(parent: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UpdaterError("Choose an existing directory for update records.")
        }
        directory = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("journal.jsonl").path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw UpdaterError("Cannot create the update journal: \(errno).") }
        journal = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try append("created", durable: true)
        try synchronizeDirectory(directory)
        try synchronizeDirectory(parent)
    }

    /// Flush intent before any destructive submission, and observed completion
    /// after validation. A durable record describes evidence, not atomic device I/O.
    func append(_ operation: String, detail: String? = nil, report: [UInt8]? = nil,
                result: Int32? = nil, durable: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        let event = Event(time: Date(), elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            operation: operation, detail: detail, report: report, result: result)
        var bytes = try encoder.encode(event)
        bytes.append(0x0A)
        try journal.write(contentsOf: bytes)
        if durable { try synchronize(journal) }
    }

    /// Exclusive creation prevents replacing evidence from a previous acquisition.
    /// Read-back equality and full synchronization gate subsequent mutation.
    func preserve(_ name: String, data: Data) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw UpdaterError("Invalid preservation filename.")
        }
        let url = directory.appendingPathComponent(name)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw UpdaterError("Cannot create preservation file \(name): \(errno).") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try synchronize(handle)
        try handle.close()
        guard try Data(contentsOf: url) == data else {
            throw UpdaterError("Preservation read-back failed for \(name).")
        }
        try synchronizeDirectory(directory)
        try append("preserved", detail: name, durable: true)
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let directoryDescriptor = open(url.path, O_RDONLY | O_DIRECTORY)
        guard directoryDescriptor >= 0 else { throw UpdaterError("Cannot synchronize preservation directory.") }
        defer { Darwin.close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else { throw UpdaterError("Cannot synchronize preservation directory.") }
    }

    private func synchronize(_ handle: FileHandle) throws {
        try handle.synchronize()
        guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == 0 else {
            throw UpdaterError("Storage could not durably flush update evidence: \(errno).")
        }
    }
}

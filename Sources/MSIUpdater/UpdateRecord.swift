import Foundation
import Darwin

/// Owner-only evidence for one device transaction. The append-only journal is the
/// source of phase history; it never authorizes retry or crash-resume.
final class UpdateRecord: @unchecked Sendable {
    struct Failure: LocalizedError, Sendable {
        let message: String
        let recordDirectory: URL
        var errorDescription: String? { message }
    }

    struct Event: Codable, Sendable {
        let time: Date
        let elapsedNanoseconds: UInt64
        let operation: String
        let detail: String?
        let report: [UInt8]?
        let result: Int32?
    }

    private struct Pending {
        let deadline: DispatchTime
        let completion: @Sendable (Result<Void, Error>) -> Void
    }

    let directory: URL
    // After initialization, only this queue touches storage and encoding. The
    // lock protects admission/completions, never I/O; HID callbacks stay responsive.
    private let io = DispatchQueue(label: "MSIUpdater.Record", qos: .utility)
    private let deadlines = DispatchQueue(label: "MSIUpdater.Record.Deadlines", qos: .utility)
    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    private var pending: [UInt64: Pending] = [:]
    private var nextID: UInt64 = 0
    private var failure: Failure?
    private let journal: FileHandle
    private let encoder: JSONEncoder
    private let started = DispatchTime.now().uptimeNanoseconds

    init(parent: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw UpdaterError("Choose an existing directory for update records.")
        }
        directory = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        timer = DispatchSource.makeTimerSource(queue: deadlines)
        // A suspended dispatch source must be resumed even if initialization fails.
        timer.resume()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        do {
            let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw UpdaterError("Cannot secure the update directory: \(errno).") }
            defer { Darwin.close(descriptor) }
            try Self.removeACL(descriptor)
            let path = directory.appendingPathComponent("journal.jsonl").path
            let journalDescriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard journalDescriptor >= 0 else { throw UpdaterError("Cannot create the update journal: \(errno).") }
            journal = FileHandle(fileDescriptor: journalDescriptor, closeOnDealloc: true)
            try Self.removeACL(journalDescriptor)
            try write(event("created"), durable: true)
            try synchronizeDirectory(directory)
            try synchronizeDirectory(parent)
        } catch {
            timer.cancel()
            throw Failure(message: error.localizedDescription, recordDirectory: directory)
        }
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.expirePendingWrites() }
    }

    deinit { timer.cancel() }

    /// Ordered and bounded. A failed or stalled write permanently closes admission;
    /// a blocked kernel write cannot be cancelled, but never holds the HID queue.
    private func enqueue(_ work: @escaping @Sendable () throws -> Void,
                         completion: @escaping @Sendable (Result<Void, Error>) -> Void) -> Bool {
        lock.lock()
        if let failure {
            lock.unlock()
            completion(.failure(failure))
            return false
        }
        guard pending.count < 8 else {
            lock.unlock()
            stop(UpdaterError("Update evidence queue exceeded its bounded capacity."))
            completion(.failure(Failure(message: "Update evidence queue is unavailable.", recordDirectory: directory)))
            return false
        }
        nextID += 1
        let id = nextID
        pending[id] = Pending(deadline: .now() + .seconds(10), completion: completion)
        // Dispatch under the admission lock so barriers cannot overtake events.
        io.async { [self] in
            lock.lock()
            let admitted = pending[id] != nil
            lock.unlock()
            guard admitted else { return }
            do {
                try work()
                lock.lock()
                let job = pending.removeValue(forKey: id)
                lock.unlock()
                job?.completion(.success(()))
            } catch { stop(error) }
        }
        lock.unlock()
        return true
    }

    private func stop(_ error: Error) {
        lock.lock()
        if failure == nil {
            failure = Failure(message: "Update evidence failed: \(error.localizedDescription)", recordDirectory: directory)
        }
        let stopped = failure!
        let jobs = Array(pending.values)
        pending.removeAll()
        lock.unlock()
        for job in jobs { job.completion(.failure(stopped)) }
    }

    private func expirePendingWrites() {
        lock.lock()
        let expired = pending.values.contains { $0.deadline <= .now() }
        lock.unlock()
        if expired { stop(UpdaterError("Storage did not finish recording update evidence within ten seconds.")) }
    }

    private func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            _ = enqueue(work) { continuation.resume(with: $0) }
        }
    }

    /// A barrier gates each device exchange on its ordered wire evidence. Durable
    /// phase intents additionally synchronize storage before destructive submission.
    func flush() async throws { try await perform {} }

    func append(_ operation: String, detail: String? = nil, report: [UInt8]? = nil,
                result: Int32? = nil, durable: Bool = false) async throws {
        let value = event(operation, detail: detail, report: report, result: result)
        try await perform { try self.write(value, durable: durable) }
    }

    /// Called on the HID state queue; admission only, with no filesystem work.
    func enqueueEvent(_ operation: String, detail: String? = nil, report: [UInt8]? = nil,
                      result: Int32? = nil,
                      completion: @escaping @Sendable (Result<Void, Error>) -> Void) -> Bool {
        let value = event(operation, detail: detail, report: report, result: result)
        return enqueue({ try self.write(value, durable: false) }, completion: completion)
    }

    private func event(_ operation: String, detail: String? = nil, report: [UInt8]? = nil, result: Int32? = nil) -> Event {
        Event(time: Date(), elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
              operation: operation, detail: detail, report: report, result: result)
    }

    private func write(_ event: Event, durable: Bool) throws {
        var bytes = try encoder.encode(event)
        bytes.append(0x0A)
        try journal.write(contentsOf: bytes)
        if durable { try synchronize(journal) }
    }

    /// Exclusive creation, read-back equality and full synchronization gate mutation.
    func preserve(_ name: String, data: Data) async throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw UpdaterError("Invalid preservation filename.")
        }
        try await perform {
            let url = self.directory.appendingPathComponent(name)
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw UpdaterError("Cannot create preservation file \(name): \(errno).") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try Self.removeACL(descriptor)
            try handle.write(contentsOf: data)
            try self.synchronize(handle)
            try handle.close()
            guard try Data(contentsOf: url) == data else {
                throw UpdaterError("Preservation read-back failed for \(name).")
            }
            try self.synchronizeDirectory(self.directory)
            try self.write(self.event("preserved", detail: name), durable: true)
        }
    }

    /// Mode bits do not revoke inherited macOS ACL grants. Clear and verify the
    /// new directory before creating sensitive children; never alter its parent.
    private static func removeACL(_ descriptor: Int32) throws {
        guard let empty = acl_init(0) else { throw UpdaterError("Cannot allocate an empty evidence ACL.") }
        defer { acl_free(UnsafeMutableRawPointer(empty)) }
        guard acl_set_fd_np(descriptor, empty, ACL_TYPE_EXTENDED) == 0 else {
            throw UpdaterError("Cannot remove inherited evidence ACL grants: \(errno).")
        }
        errno = 0
        guard let actual = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            // APFS reports an absent extended ACL as ENOENT after clearing it.
            guard errno == ENOENT else { throw UpdaterError("Cannot verify the evidence ACL: \(errno).") }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(actual)) }
        var entry: acl_entry_t?
        errno = 0
        let result = acl_get_entry(actual, ACL_FIRST_ENTRY.rawValue, &entry)
        // Darwin returns zero for an entry, -1/EINVAL for the empty list.
        guard result == -1, errno == EINVAL else {
            throw UpdaterError("The evidence ACL could not be verified empty.")
        }
    }

    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw UpdaterError("Cannot synchronize preservation directory.") }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw UpdaterError("Cannot synchronize preservation directory.") }
    }

    private func synchronize(_ handle: FileHandle) throws {
        try handle.synchronize()
        guard fcntl(handle.fileDescriptor, F_FULLFSYNC) == 0 else {
            throw UpdaterError("Storage could not durably flush update evidence: \(errno).")
        }
    }
}

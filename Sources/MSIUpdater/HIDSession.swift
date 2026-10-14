import Foundation
import IOKit.hid
import Darwin

/// A missing input reply is distinct from failed output, cancellation or removal.
/// Only independently addressed physical reads may reopen.
struct HIDResponseTimeout: LocalizedError, Sendable {
    var errorDescription: String? { "Monitor input reply timed out after successful output completion." }
}

/// One canonical transport owner. Reopening replaces only the host HID channel;
/// it never resets the monitor, changes interfaces or replays a device command.
actor HIDSession {
    private enum State { case ready, exchanging, reopening, closed }
    private var state = State.ready
    private var channel: HIDChannel
    private let identity: MonitorDevice
    private let record: UpdateRecord?

    init(identity: MonitorDevice, record: UpdateRecord? = nil) throws {
        self.identity = identity
        self.record = record
        channel = try HIDChannel(identity: identity, record: record)
    }

    func exchange(_ packet: [UInt8], expectsReply: Bool = true) async throws -> [UInt8] {
        guard state == .ready else { throw UpdaterError("Monitor session is unavailable or busy.") }
        state = .exchanging
        defer { if state == .exchanging { state = .ready } }
        try await record?.flush()
        guard state == .exchanging else { throw UpdaterError("Monitor session closed while recording evidence.") }
        let response: [UInt8]
        do { response = try await channel.exchange(packet, expectsReply: expectsReply) }
        catch {
            let transportError = error
            do { try await record?.flush() }
            catch {
                throw UpdaterError("\(transportError.localizedDescription) Evidence: \(error.localizedDescription)")
            }
            throw transportError
        }
        try await record?.flush()
        return response
    }

    func close() async {
        state = .closed
        await channel.close()
    }

    /// Caller must have observed a missing reply, with no uncertain flash or
    /// protection mutation. Its operation-specific identity checks and bounded
    /// replay rules gate further commands.
    func reopenAfterReplyTimeout() async throws {
        try Task.checkCancellation()
        guard state == .ready else { throw UpdaterError("Cannot reopen a busy or closed monitor session.") }
        state = .reopening
        await channel.close()
        do {
            try Task.checkCancellation()
            guard state == .reopening else { throw UpdaterError("Monitor session closed during reopen.") }
            // HIDChannel binds the same serial, location and registry service;
            // a device reset/re-enumeration therefore cannot pass this gate.
            try await record?.append("channel-reopen-intent", durable: true)
            guard state == .reopening else { throw UpdaterError("Monitor session closed while recording reopen intent.") }
            channel = try HIDChannel(identity: identity, record: record)
            state = .ready
            try await record?.append("channel-reopened", durable: true)
        } catch {
            state = .closed
            await channel.close()
            throw error
        }
    }
}

/// Transaction state belongs to queue. A dedicated run loop receives native HID
/// events and copies reports promptly; it never journals or starts another command.
/// This scheduling passed the read sweep that failed under dispatch delivery.
/// Callback contexts/buffers outlive native unscheduling and pending cancellation.
final class HIDChannel: @unchecked Sendable {
    /// Cancellation can occur while submission is waiting on the HID queue.
    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private final class Output {
        let bytes: UnsafeMutablePointer<UInt8>
        let session: HIDChannel
        let sequence: UInt64

        init(_ packet: [UInt8], session: HIDChannel, sequence: UInt64) {
            bytes = .allocate(capacity: packet.count)
            bytes.initialize(from: packet, count: packet.count)
            self.session = session
            self.sequence = sequence
        }

        deinit { bytes.deallocate() }
    }

    private struct Pending {
        let sequence: UInt64
        let reportID: UInt8
        let expectsReply: Bool
        let continuation: CheckedContinuation<[UInt8], Error>
        var submittedAtMach: UInt64 = 0
        var outputComplete = false
        var response: [UInt8]?
    }

    private let queue = DispatchQueue(label: "MSIUpdater.HID")
    private let device: IOHIDDevice
    private let record: UpdateRecord?
    private let input: UnsafeMutablePointer<UInt8>
    // Published before the initialization semaphore is signalled, then immutable.
    private var nativeLoop: CFRunLoop?
    private var pending: Pending?
    private var sequence: UInt64 = 0
    private var cancelled = false
    private var closed = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(identity: MonitorDevice, record: UpdateRecord? = nil) throws {
        self.record = record
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1462, kIOHIDProductIDKey: 0x3FA4] as CFDictionary)
        let candidates = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let matches = candidates.filter { candidate in
            var id: UInt64 = 0
            return IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(candidate), &id) == KERN_SUCCESS && id == identity.id
        }
        guard matches.count == 1, let selected = matches.first,
              try MonitorDevice.discover().contains(where: { $0.id == identity.id && $0.serial == identity.serial && $0.location == identity.location }) else {
            throw UpdaterError("The selected monitor disconnected or changed. Refresh its identity.")
        }
        device = selected
        let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard opened == kIOReturnSuccess else {
            throw UpdaterError("Cannot acquire the monitor’s USB controller (\(opened)). Close other monitor-control apps or release VM passthrough.")
        }
        input = .allocate(capacity: 64)
        input.initialize(repeating: 0, count: 64)
        let context = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, input, 64, { context, result, _, type, reportID, bytes, length, timestamp in
            guard let context else { return }
            let session = Unmanaged<HIDChannel>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
                  length == 64, reportID <= 255 else {
                session.queue.async { session.fail(UpdaterError("Invalid HID input report.")) }; return
            }
            let copy = Array(UnsafeBufferPointer(start: bytes, count: length))
            let callbackTime = mach_absolute_time()
            session.queue.async { session.received(copy, reportID: UInt8(reportID), timestamp: timestamp, callbackTime: callbackTime) }
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let session = Unmanaged<HIDChannel>.fromOpaque(context).takeUnretainedValue()
            session.queue.async { session.fail(UpdaterError("Monitor disconnected; the pending operation’s outcome is unknown.")) }
        }, context)
        let ready = DispatchSemaphore(value: 0)
        let contextAddress = UInt(bitPattern: context)
        Thread.detachNewThread { [self] in
            Thread.current.name = "MSIUpdater.HID.Input"
            let loop = CFRunLoopGetCurrent()!
            nativeLoop = loop
            IOHIDDeviceScheduleWithRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            ready.signal()
            CFRunLoopRun()
            IOHIDDeviceUnscheduleFromRunLoop(device, loop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(0))
            queue.async { [self] in
                // Input is unscheduled; already copied callbacks drain before
                // this transition. Output keeps its context until its actual
                // completion/abort callback. Older macOS may retain pending
                // output longer; see docs/app/reliability.md.
                cancelled = true
                fail(UpdaterError("Monitor input processing ended."))
                input.deallocate()
                closed = true
                let waiters = closeWaiters
                closeWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
                Unmanaged<HIDChannel>.fromOpaque(UnsafeMutableRawPointer(bitPattern: contextAddress)!).release()
            }
        }
        ready.wait()
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.closed { continuation.resume(); return }
                self.closeWaiters.append(continuation)
                self.fail(UpdaterError("Monitor session closed."))
            }
        }
    }

    /// A timeout invalidates this session. It never means a command had no effect.
    func exchange(_ packet: [UInt8], expectsReply: Bool = true) async throws -> [UInt8] {
        guard packet.count == 64, [UInt8(1), 2, 4].contains(packet[0]) else {
            throw UpdaterError("Invalid outgoing HID report.")
        }
        try Task.checkCancellation()
        let cancellation = CancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !cancellation.isCancelled, !self.cancelled, self.pending == nil else {
                        continuation.resume(throwing: UpdaterError("Monitor session is unavailable or busy.")); return
                    }
                    self.sequence += 1
                    let number = self.sequence
                    self.pending = Pending(sequence: number, reportID: packet[0], expectsReply: expectsReply, continuation: continuation)
                    guard self.log("output-submit", report: packet, detail: "sequence=\(number) submitMach=\(mach_absolute_time())") else { return }
                    guard !cancellation.isCancelled else {
                        self.fail(UpdaterError("Monitor operation cancelled before submission."))
                        return
                    }
                    let output = Output(packet, session: self, sequence: number)
                    let context = Unmanaged.passRetained(output).toOpaque()
                    self.pending?.submittedAtMach = mach_absolute_time()
                    let result = IOHIDDeviceSetReportWithCallback(self.device, kIOHIDReportTypeOutput,
                        CFIndex(packet[0]), output.bytes, 64, 1500, { context, result, _, _, _, _, _ in
                            guard let context else { return }
                            let output = Unmanaged<Output>.fromOpaque(context).takeRetainedValue()
                            let session = output.session
                            let sequence = output.sequence
                            session.queue.async { session.completed(result, sequence: sequence) }
                        }, context)
                    let recorded = self.log("output-submission-result", result: result)
                    if result != kIOReturnSuccess {
                        Unmanaged<Output>.fromOpaque(context).release()
                        self.fail(UpdaterError("HID submission failed (\(result)).")); return
                    }
                    guard recorded else { return }
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        guard let pending = self.pending, pending.sequence == number else { return }
                        // A missing output callback is uncertain submission, not read reply loss.
                        // Output retains its buffer/session until completion even after cancellation.
                        if pending.outputComplete, pending.expectsReply, pending.response == nil {
                            self.fail(HIDResponseTimeout())
                        } else {
                            self.fail(UpdaterError("HID output completion timed out; device outcome is uncertain."))
                        }
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
            self.queue.async {
                self.fail(UpdaterError("Monitor operation cancelled; an already submitted command may have taken effect."))
            }
        }
    }

    private func received(_ bytes: [UInt8], reportID: UInt8, timestamp: UInt64, callbackTime: UInt64) {
        guard log("input", report: bytes, detail: "hidTimestamp=\(timestamp) callbackMach=\(callbackTime)") else { return }
        guard var current = pending else {
            fail(UpdaterError("Unexpected input outside a monitor transaction.")); return
        }
        guard timestamp >= current.submittedAtMach, current.submittedAtMach != 0 else {
            fail(UpdaterError("A stale HID report predates this request; stop without replay.")); return
        }
        guard current.expectsReply, current.response == nil,
              reportID == current.reportID, bytes[0] == reportID else {
            fail(UpdaterError("Unexpected or duplicate monitor response.")); return
        }
        current.response = bytes
        pending = current
        finishIfReady()
    }

    private func completed(_ result: IOReturn, sequence: UInt64) {
        guard log("output-completion", result: result, detail: "sequence=\(sequence) completionMach=\(mach_absolute_time())") else { return }
        guard var current = pending, current.sequence == sequence else { return }
        guard result == kIOReturnSuccess else {
            fail(UpdaterError("HID output failed (\(result)); device outcome is uncertain.")); return
        }
        current.outputComplete = true
        pending = current
        finishIfReady()
    }

    private func finishIfReady() {
        guard let current = pending, current.outputComplete,
              !current.expectsReply || current.response != nil else { return }
        pending = nil
        current.continuation.resume(returning: current.response ?? [])
    }

    private func fail(_ error: Error) {
        if let current = pending {
            pending = nil
            current.continuation.resume(throwing: error)
        }
        if !cancelled {
            cancelled = true
            if let loop = nativeLoop {
                CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { CFRunLoopStop(loop) }
                CFRunLoopWakeUp(loop)
            }
        }
    }

    private func log(_ operation: String, report: [UInt8]? = nil, result: Int32? = nil, detail: String? = nil) -> Bool {
        guard let record else { return true }
        return record.enqueueEvent(operation, detail: detail, report: report, result: result) { outcome in
            if case .failure(let error) = outcome {
                self.queue.async { self.fail(error) }
            }
        }
    }
}

import Foundation
import IssueReporting

/// Captures unary callback-style completions and lets a test invoke or release
/// them explicitly.
///
/// Capture a completion from a `thenEscaping` handler, then drive it after
/// the subject under test has reached the desired state:
///
/// ```swift
/// let completion = CallbackCapture<Result>()
/// stub.when { $0.load(completion: Match.any()) }.thenEscaping { callback in
///     completion.capture(callback)
/// }
/// await completion.waitForCallback(within: .seconds(1))
/// completion.invokeNext(.success(value))
/// completion.assertReleased()
/// ```
public final class CallbackCapture<Value>: @unchecked Sendable {
    /// The captured completion shape.
    public typealias Callback = (Value) -> Void

    private let lock = NSLock()
    private var callbacks: [Callback] = []
    private var configuredName: String?
    private var nextWaiterID: UInt64 = 0
    private var waiters: [UInt64: CallbackCaptureWaiter] = [:]
    private var pendingWaiterIDs: Set<UInt64> = []
    private var cancelledWaiterIDs: Set<UInt64> = []

    /// Creates an empty callback capture.
    public init() {
        TestDoubleTestingContext.session?.register(
            TestDoubleTeardownCheck(kind: .callbackCapture) { [weak self] in
                self?.teardownDiagnostic()
            }
        )
    }

    /// Assigns a name used in automatic test-double teardown diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            trimmedName.isEmpty == false,
            "[TestDoubles] A callback capture name must not be empty."
        )
        lock.withLock { configuredName = trimmedName }
        return self
    }

    /// Number of callback closures currently retained for test control.
    public var pendingCount: Int {
        lock.withLock { callbacks.count }
    }

    /// Retains `callback` until it is invoked or released.
    public func capture(_ callback: @escaping Callback) {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
            callbacks.append(callback)
            let readyIDs = waiters.compactMap { id, waiter in
                waiter.minimumCount <= callbacks.count ? id : nil
            }
            return readyIDs.compactMap { waiters.removeValue(forKey: $0)?.continuation }
        }
        ready.forEach { $0.resume() }
    }

    /// Waits up to `timeout` for at least `count` callbacks to be captured.
    ///
    /// A timeout reports a test issue at this call site. Cancelling the
    /// awaiting task returns without reporting and does not release any
    /// callbacks.
    public func waitForCallback(
        count: Int = 1,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await waitForCallback(
            count: count,
            within: timeout,
            using: StubClocks.continuous,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for captured callbacks using `clock` rather than wall time.
    ///
    /// Use ``TestDoubleClock`` to advance timeout-sensitive tests
    /// deterministically.
    public func waitForCallback(
        count: Int = 1,
        within timeout: Duration,
        using clock: any StubClock,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        precondition(
            count >= 1,
            "[TestDoubles] waitForCallback(count:) requires a count of at least 1."
        )
        precondition(
            timeout >= .zero,
            "[TestDoubles] waitForCallback(within:) requires a nonnegative timeout."
        )

        let outcome = await withTaskGroup(of: CallbackCaptureWaitOutcome.self) { group in
            group.addTask { [self] in
                await waitForCallbacksUntilCancelled(count: count)
                    ? .satisfied
                    : .cancelled
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }

            guard let result = await group.next() else {
                return CallbackCaptureWaitOutcome.cancelled
            }
            group.cancelAll()
            return result
        }

        guard outcome == .timedOut else { return }
        let actualCount = pendingCount
        reportIssue(
            "[TestDoubles] Expected at least \(count) captured "
                + "\(count == 1 ? "callback" : "callbacks") within \(timeout), "
                + "but \(actualCount) \(actualCount == 1 ? "callback is" : "callbacks are") pending.",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Invokes and releases the oldest captured callback.
    public func invokeNext(_ value: Value) {
        let callback: Callback = lock.withLock {
            guard callbacks.isEmpty == false else {
                preconditionFailure(
                    "[TestDoubles] No captured callback is available to invoke. "
                        + "Exercise the dependency and wait for its callback registration first."
                )
            }
            return callbacks.removeFirst()
        }
        callback(value)
    }

    /// Invokes the oldest callback `count` times, then releases it.
    ///
    /// Repeating a completion is intentionally explicit because most APIs
    /// promise one completion. It is useful for testing defensive clients of
    /// legacy or third-party callbacks.
    public func invokeNext(repeating count: Int, _ value: Value) {
        precondition(count >= 1, "[TestDoubles] Callback repetition count must be at least 1.")
        let callback: Callback = lock.withLock {
            guard callbacks.isEmpty == false else {
                preconditionFailure("[TestDoubles] No captured callback is available to invoke.")
            }
            return callbacks.removeFirst()
        }
        for _ in 0 ..< count { callback(value) }
    }

    /// Invokes and releases every currently captured callback with `value`, in
    /// capture order.
    public func invokeAll(_ value: Value) {
        let pending: [Callback] = lock.withLock {
            defer { callbacks.removeAll(keepingCapacity: true) }
            return callbacks
        }
        pending.forEach { $0(value) }
    }

    /// Releases every callback without invoking it, modelling a request that
    /// was abandoned or a dependency that was torn down.
    public func releaseAll() {
        lock.withLock { callbacks.removeAll(keepingCapacity: true) }
    }

    /// Reports a test issue if callbacks are still retained by this control.
    /// Call this at teardown to make accidental callback retention visible.
    public func assertReleased(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let count = pendingCount
        guard count > 0 else { return }
        reportIssue(
            "[TestDoubles] Expected captured callbacks to be released, but \(count) "
                + "\(count == 1 ? "callback remains" : "callbacks remain").",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension CallbackCapture {
    private func waitForCallbacksUntilCancelled(count: Int) async -> Bool {
        let waiterID = lock.withLock {
            defer { nextWaiterID &+= 1 }
            pendingWaiterIDs.insert(nextWaiterID)
            return nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResume = lock.withLock { () -> Bool in
                    if cancelledWaiterIDs.remove(waiterID) != nil {
                        return true
                    }
                    pendingWaiterIDs.remove(waiterID)
                    if callbacks.count >= count {
                        return true
                    }
                    waiters[waiterID] = CallbackCaptureWaiter(
                        minimumCount: count,
                        continuation: continuation
                    )
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                if let waiter = waiters.removeValue(forKey: waiterID) {
                    return waiter.continuation
                }
                if pendingWaiterIDs.remove(waiterID) != nil {
                    cancelledWaiterIDs.insert(waiterID)
                }
                return nil
            }
            continuation?.resume()
        }
        return Task.isCancelled == false
    }

    func teardownDiagnostic() -> String? {
        let (count, name) = lock.withLock { (callbacks.count, configuredName) }
        guard count > 0 else { return nil }
        let subject = name.map { " '\($0)'" } ?? ""
        return "Expected captured callbacks\(subject) to be released, but \(count) "
            + "\(count == 1 ? "callback remains" : "callbacks remain")."
    }
}

private struct CallbackCaptureWaiter {
    let minimumCount: Int
    let continuation: CheckedContinuation<Void, Never>
}

private enum CallbackCaptureWaitOutcome: Sendable {
    case satisfied
    case timedOut
    case cancelled
}

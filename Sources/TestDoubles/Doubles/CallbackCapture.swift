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
/// stub.when { $0.load(completion: any()) }.thenEscaping { callback in
///     completion.capture(callback)
/// }
/// completion.invokeNext(.success(value))
/// completion.assertReleased()
/// ```
public final class CallbackCapture<Value> {
    /// The captured completion shape.
    public typealias Callback = (Value) -> Void

    private let lock = NSLock()
    private var callbacks: [Callback] = []
    private var configuredName: String?

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
        lock.withLock { callbacks.append(callback) }
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
    func teardownDiagnostic() -> String? {
        let (count, name) = lock.withLock { (callbacks.count, configuredName) }
        guard count > 0 else { return nil }
        let subject = name.map { " '\($0)'" } ?? ""
        return "Expected captured callbacks\(subject) to be released, but \(count) "
            + "\(count == 1 ? "callback remains" : "callbacks remain")."
    }
}

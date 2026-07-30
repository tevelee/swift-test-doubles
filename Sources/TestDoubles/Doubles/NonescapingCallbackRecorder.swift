import Foundation

/// Records safe, immediate invocations of a nonescaping callback.
///
/// The callback is never retained or placed in interaction history. Only its
/// copyable input, returned values, and thrown errors are stored. This makes
/// the recorder suitable inside synchronous dependency implementations whose
/// callback parameter is nonescaping:
///
/// ```swift
/// let callbacks = NonescapingCallbackRecorder<Int, String>()
///
/// func perform(callback: (Int) -> String) -> String {
///     callbacks.invoke(callback, with: 42)
/// }
/// ```
///
/// Use ``CallbackCapture`` instead when an escaping callback must be invoked
/// later.
public final class NonescapingCallbackRecorder<Input, Result> {
    /// The nonescaping callback shape accepted by `invoke(_:with:)`.
    public typealias Callback = (Input) -> Result

    private let lock = NSLock()
    private var recordedInputs: [Input] = []
    private var recordedResults: [Result] = []
    private var recordedErrors: [any Error] = []

    /// Creates an empty callback recorder.
    public init() {}

    /// Invokes `callback` immediately and records its input and result.
    ///
    /// `callback` deliberately has no `@escaping` annotation.
    @discardableResult
    public func invoke(
        _ callback: Callback,
        with input: Input
    ) -> Result {
        lock.withLock {
            recordedInputs.append(input)
        }
        let result = callback(input)
        lock.withLock {
            recordedResults.append(result)
        }
        return result
    }

    /// Invokes a typed-throwing callback immediately.
    ///
    /// Successful results and thrown errors are recorded separately while the
    /// precise `Failure` channel is preserved for the caller.
    @discardableResult
    public func invoke<Failure: Error>(
        _ callback: (Input) throws(Failure) -> Result,
        with input: Input
    ) throws(Failure) -> Result {
        lock.withLock {
            recordedInputs.append(input)
        }
        do {
            let result = try callback(input)
            lock.withLock {
                recordedResults.append(result)
            }
            return result
        } catch {
            lock.withLock {
                recordedErrors.append(error)
            }
            throw error
        }
    }

    /// Number of callback invocations that entered the recorder.
    public var callCount: Int {
        lock.withLock { recordedInputs.count }
    }

    /// Inputs in invocation-entry order.
    public var invocations: [Input] {
        lock.withLock { recordedInputs }
    }

    /// Successfully returned values in completion order.
    public var results: [Result] {
        lock.withLock { recordedResults }
    }

    /// Thrown errors in completion order.
    public var errors: [any Error] {
        lock.withLock { recordedErrors }
    }

    /// Clears recorded inputs, results, and errors.
    public func reset() {
        lock.withLock {
            recordedInputs.removeAll(keepingCapacity: true)
            recordedResults.removeAll(keepingCapacity: true)
            recordedErrors.removeAll(keepingCapacity: true)
        }
    }
}

extension NonescapingCallbackRecorder where Result == Void {
    /// Invokes `callback` immediately for every supplied input.
    public func invoke(
        _ callback: Callback,
        with inputs: Input...
    ) {
        for input in inputs {
            invoke(callback, with: input)
        }
    }
}

extension NonescapingCallbackRecorder: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

import Foundation

/// A handle to calls parked by `thenSuspend()`.
///
/// The test awaits a call's arrival with ``waitForCall(count:)``, asserts
/// whatever must hold while the call is in flight, then completes it with
/// ``resume(returning:)`` or ``resume(throwing:)``. Parked calls resume in
/// arrival order, one per `resume`. A parked call stays suspended even if its
/// task is cancelled; this handle is the only thing that completes it.
public final class StubSuspension<Result> {
    private typealias Outcome = Swift.Result<Any, any Error>

    private let recorder: StubRecorder
    private let method: MethodDescriptor
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Outcome, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(recorder: StubRecorder, method: MethodDescriptor) {
        self.recorder = recorder
        self.method = method
    }

    /// Suspends until at least `count` matching calls are currently parked,
    /// returning immediately when they already are. Resumed calls leave the
    /// parked set, so `count` describes calls now in flight, not a running
    /// total of arrivals.
    public func waitForCall(count: Int = 1) async {
        precondition(
            count >= 1,
            "[TestDoubles] waitForCall(count:) requires a count of at least 1."
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if parked.count >= count {
                lock.unlock()
                continuation.resume()
                return
            }
            arrivalWaiters.append((count, continuation))
            lock.unlock()
        }
    }

    /// Completes the oldest parked call by returning `value`.
    public func resume(returning value: sending Result) {
        recorder.requireReturnValueMatchesRuntimeType(value, for: method.index)
        completeOldest(with: .success(value))
    }

    /// Completes the oldest parked call by throwing `error`.
    ///
    /// The suspended requirement must be throwing. For a concrete
    /// typed-throws requirement, `error` must be compatible with its declared
    /// error type.
    public func resume<Failure: Error>(throwing error: Failure) {
        guard method.isThrowing else {
            fatalError(
                "[TestDoubles] resume(throwing:) requires a throwing requirement; "
                    + "\(method.name) cannot throw."
            )
        }
        recorder.requireThrownErrorMatchesRuntimeType(error, for: method)
        completeOldest(with: .failure(error))
    }

    /// Parks the stubbed call's task until the test resumes it. Runs as the
    /// registration's suspending behavior, on the call's own task.
    func park() async throws -> Any {
        let outcome = await withCheckedContinuation {
            (continuation: CheckedContinuation<Outcome, Never>) in
            lock.lock()
            parked.append(continuation)
            let parkedCount = parked.count
            var satisfied: [CheckedContinuation<Void, Never>] = []
            arrivalWaiters.removeAll { waiter in
                guard waiter.count <= parkedCount else { return false }
                satisfied.append(waiter.continuation)
                return true
            }
            lock.unlock()
            satisfied.forEach { $0.resume() }
        }
        return try outcome.get()
    }

    private func completeOldest(with outcome: sending Outcome) {
        lock.lock()
        guard parked.isEmpty == false else {
            lock.unlock()
            fatalError(
                "[TestDoubles] No suspended call to resume for \(method.name). "
                    + "Await waitForCall() first so the call has arrived and parked."
            )
        }
        let continuation = parked.removeFirst()
        lock.unlock()
        continuation.resume(returning: outcome)
    }
}

/// The suspension crosses concurrency domains by design: the stubbed call
/// parks on its own task while the test drives the handle. Internal state is
/// guarded by the lock.
extension StubSuspension: @unchecked Sendable where Result: Sendable {}

extension StubSuspension where Result == Void {
    /// Completes the oldest parked `Void` call.
    public func resume() {
        resume(returning: ())
    }
}

import InternalRuntimeContract
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
    private let method: RuntimeMethod
    private let state = StubSuspensionState()

    init(recorder: StubRecorder, method: RuntimeMethod) {
        self.recorder = recorder
        self.method = method
    }

    /// Suspends until at least `count` matching calls are currently parked,
    /// returning immediately when they already are. Resumed calls leave the
    /// parked set, so `count` describes calls now in flight, not a running
    /// total of arrivals. Cancelling the waiting task also returns immediately
    /// without affecting parked calls.
    public func waitForCall(count: Int = 1) async {
        precondition(
            count >= 1,
            "[TestDoubles] waitForCall(count:) requires a count of at least 1."
        )

        let state = self.state
        let waiterID = state.lock.withLock {
            defer { state.nextArrivalWaiterID &+= 1 }
            state.pendingArrivalWaiterIDs.insert(state.nextArrivalWaiterID)
            return state.nextArrivalWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResume = state.lock.withLock { () -> Bool in
                    if state.cancelledArrivalWaiterIDs.remove(waiterID) != nil {
                        return true
                    }
                    state.pendingArrivalWaiterIDs.remove(waiterID)
                    if state.parked.count >= count {
                        return true
                    }
                    state.arrivalWaiters[waiterID] = StubSuspensionArrivalWaiter(
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
            let continuation = state.lock.withLock { () -> CheckedContinuation<Void, Never>? in
                if let waiter = state.arrivalWaiters.removeValue(forKey: waiterID) {
                    return waiter.continuation
                }
                if state.pendingArrivalWaiterIDs.remove(waiterID) != nil {
                    state.cancelledArrivalWaiterIDs.insert(waiterID)
                }
                return nil
            }
            continuation?.resume()
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
            state.lock.lock()
            state.parked.append(continuation)
            let parkedCount = state.parked.count
            let satisfiedIDs = state.arrivalWaiters.compactMap { id, waiter in
                waiter.minimumCount <= parkedCount ? id : nil
            }
            let satisfied = satisfiedIDs.compactMap {
                state.arrivalWaiters.removeValue(forKey: $0)?.continuation
            }
            state.lock.unlock()
            satisfied.forEach { $0.resume() }
        }
        return try outcome.get()
    }

    private func completeOldest(with outcome: sending Outcome) {
        state.lock.lock()
        guard state.parked.isEmpty == false else {
            state.lock.unlock()
            fatalError(
                "[TestDoubles] No suspended call to resume for \(method.name). "
                    + "Await waitForCall() first so the call has arrived and parked."
            )
        }
        let continuation = state.parked.removeFirst()
        state.lock.unlock()
        continuation.resume(returning: outcome)
    }
}

/// The suspension crosses concurrency domains by design: the stubbed call
/// parks on its own task while the test drives the handle. Internal state is
/// guarded by the lock.
extension StubSuspension: @unchecked Sendable where Result: Sendable {}

extension StubSuspension {
    func teardownDiagnostic() -> String? {
        let pendingCount = state.lock.withLock { state.parked.count }
        guard pendingCount > 0 else { return nil }
        let subject = recorder.testDoubleName.map { " for test double '\($0)'" } ?? ""
        return "Expected every suspended call\(subject) for \(method.name) to be resumed, "
            + "but \(pendingCount) \(pendingCount == 1 ? "call remains parked" : "calls remain parked")."
    }
}

private struct StubSuspensionArrivalWaiter {
    let minimumCount: Int
    let continuation: CheckedContinuation<Void, Never>
}

private final class StubSuspensionState: @unchecked Sendable {
    let lock = NSLock()
    var parked: [CheckedContinuation<Swift.Result<Any, any Error>, Never>] = []
    var nextArrivalWaiterID: UInt64 = 0
    var arrivalWaiters: [UInt64: StubSuspensionArrivalWaiter] = [:]
    var pendingArrivalWaiterIDs: Set<UInt64> = []
    var cancelledArrivalWaiterIDs: Set<UInt64> = []
}

extension StubSuspension where Result == Void {
    /// Completes the oldest parked `Void` call.
    public func resume() {
        resume(returning: ())
    }
}

import Foundation

/// A clock used by delayed test-double behaviors.
///
/// Pass a custom clock to `thenReturn(after:using:)` or
/// `thenThrow(after:using:)` to make timing deterministic in a test. The
/// default overloads continue to use continuous wall-clock time.
public protocol StubClock: Sendable {
    /// Suspends for the requested duration.
    ///
    /// Implementations must respect task cancellation so an eventual
    /// verification can stop its losing timeout race promptly.
    func sleep(for duration: Duration) async throws
}

/// Built-in clocks for delayed stub behaviors.
public enum StubClocks {
    /// The production-like clock used by existing `after:` overloads.
    public static let continuous: any StubClock = ContinuousStubClock()
    /// A clock that completes delays immediately, useful when only the
    /// behavior shape—not elapsed time—is under test.
    public static let immediate: any StubClock = ImmediateStubClock()
}

private struct ContinuousStubClock: StubClock {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

private struct ImmediateStubClock: StubClock {
    func sleep(for _: Duration) async throws {}
}

/// A manually advanced clock for deterministic delayed stub behaviors.
///
/// Calls remain suspended until the test advances the clock far enough. This
/// is intentionally small and dependency-free; it can be used anywhere a
/// test does not already have a project-wide clock abstraction.
public final class ManualStubClock: StubClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var elapsed: Duration = .zero
    private var nextSleeperID: UInt64 = 0
    private var sleepers: [UInt64: Sleeper] = [:]
    private var cancelledSleeperIDs: Set<UInt64> = []

    public init() {}

    /// Number of delayed behaviors currently waiting on this clock.
    public var pendingSleepCount: Int {
        lock.withLock { sleepers.count }
    }

    public func sleep(for duration: Duration) async throws {
        precondition(duration >= .zero, "[TestDoubles] A clock delay must be nonnegative.")
        let sleeperID = lock.withLock {
            defer { nextSleeperID &+= 1 }
            return nextSleeperID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancellation = lock.withLock { () -> Bool in
                    if cancelledSleeperIDs.remove(sleeperID) != nil {
                        return true
                    }
                    sleepers[sleeperID] = Sleeper(
                        deadline: elapsed + duration,
                        continuation: continuation
                    )
                    return false
                }
                if cancellation {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                if let sleeper = sleepers.removeValue(forKey: sleeperID) {
                    return sleeper.continuation
                }
                cancelledSleeperIDs.insert(sleeperID)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Advances time and resumes every delayed behavior whose deadline has
    /// passed.
    public func advance(by duration: Duration) {
        precondition(duration >= .zero, "[TestDoubles] Clock advancement must be nonnegative.")
        let ready: [Sleeper] = lock.withLock {
            elapsed += duration
            let ready = sleepers.values.filter { $0.deadline <= elapsed }
            sleepers = sleepers.filter { $0.value.deadline > elapsed }
            return ready
        }
        ready.forEach { $0.continuation.resume() }
    }

    /// Resumes every delayed behavior regardless of its requested delay.
    public func advanceToEnd() {
        let ready: [Sleeper] = lock.withLock {
            defer { sleepers.removeAll() }
            return Array(sleepers.values)
        }
        ready.forEach { $0.continuation.resume() }
    }
}

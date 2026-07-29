/// Monotonic timing information for one invocation.
///
/// `startedAt` and `completedAt` use `ContinuousClock` so elapsed durations
/// are unaffected by wall-clock changes.
public struct InvocationTiming: Sendable, Identifiable {
    /// The invocation's process-global entry order.
    public let id: UInt64
    /// The instant at which the call entered the double.
    public let startedAt: ContinuousClock.Instant
    /// The instant at which the call returned, threw, or finished forwarding.
    public let completedAt: ContinuousClock.Instant?
    /// The elapsed time from entry to completion, or `nil` while pending.
    public let duration: Duration?
}

extension RecordedCall {
    var timing: InvocationTiming? {
        guard let sequence, let startedAt else { return nil }
        return InvocationTiming(
            id: sequence,
            startedAt: startedAt,
            completedAt: completedAt,
            duration: completedAt.map { startedAt.duration(to: $0) }
        )
    }
}

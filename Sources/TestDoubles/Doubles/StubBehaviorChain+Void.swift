/// A behavior chain can cross concurrency domains when its fixed result can.
/// Finish configuring the chain before matching invocations begin.
extension StubBehaviorChain: @unchecked Sendable where Result: Sendable {}

extension StubBehaviorChain where Result == Void {
    /// Appends a no-op behavior to the behavior chain. With nothing appended
    /// after it, this behaves like `times: 1...` (repeats forever).
    @_disfavoredOverload
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: ClosedRange<Int>
    ) -> Self {
        thenReturn((), after: delay, times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations,
    /// and requires the chain to be continued or explicitly discarded.
    public func thenDoNothing(after delay: Duration? = nil, times: ClosedRange<Int>) {
        thenReturn((), after: delay, times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenDoNothing(after delay: Duration? = nil, times: Int = 1) -> Self {
        thenReturn((), after: delay, times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    public func thenDoNothing(after delay: Duration? = nil, times: Int) {
        thenReturn((), after: delay, times: times)
    }

    /// Appends a no-op behavior for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it.
    public func thenDoNothing(after delay: Duration? = nil, times: PartialRangeFrom<Int> = 1...) {
        thenReturn((), after: delay, times: times)
    }
}

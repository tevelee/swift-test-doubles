/// A behavior chain can cross concurrency domains when its fixed result can.
/// Finish configuring the chain before matching invocations begin.
extension StubBehaviorChain: @unchecked Sendable where Result: Sendable {}

extension StubBehaviorChain where Result == Void {
    /// Appends a no-op behavior for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(after delay: Duration? = nil, times: Int = 1) -> Self {
        thenReturn((), after: delay, times: times)
    }

    /// Appends a no-op behavior for every matching invocation from here on.
    ///
    /// This is terminal: the returned handle supports interaction operations
    /// but no further behavior can be chained after it.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        thenReturn((), after: delay, times: times)
    }
}

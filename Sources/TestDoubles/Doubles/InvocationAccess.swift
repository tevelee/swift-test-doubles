extension Stub {
    /// Returns a human-readable, ordered log of every recorded invocation,
    /// one call per line, for debugging.
    ///
    /// When a verification fails, print this value to see the complete
    /// interaction history with recorded arguments woven into the
    /// requirement's labels:
    ///
    /// ```swift
    /// print(analytics.describeInteractions())
    /// // [TestDoubles] Recorded 3 interactions in order:
    /// //   #1  track(event: "add_to_cart", value: 30)
    /// //   #2  track(event: "add_to_cart", value: 12)
    /// //   #3  track(event: "purchase", value: 42)
    /// ```
    ///
    /// This is a diagnostic query. It does not verify calls, consume
    /// configured behavior, or commit captures. Forwarded calls on a ``Spy``
    /// are included like any other recorded call.
    public func describeInteractions() -> String {
        recorder.interactionLog()
    }
}

extension ManualStub {
    /// Returns a human-readable, ordered log of every recorded invocation.
    ///
    /// The format and query-only behavior match
    /// ``Stub/describeInteractions()``.
    public func describeInteractions() -> String {
        recorder.interactionLog()
    }
}

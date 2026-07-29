extension CallPattern {
    /// Cancels the calling task after `delay`, then throws
    /// `CancellationError`.
    ///
    /// The requirement must be async and able to throw `CancellationError`.
    /// Use the `returning:` overload for a nonthrowing async requirement.
    @discardableResult
    public func thenCancel(
        after delay: Duration,
        using clock: any StubClock = StubClocks.continuous
    ) -> CallInteractions {
        let method = requireAsyncRequirement(configuring: "thenCancel")
        requireValidThrownError(CancellationError(), for: method)
        _ = makeBehaviorChain([
            (
                cancelAfterAnswer(delay, using: clock, outcome: nil),
                .unbounded
            )
        ])
        return interactions
    }

    /// Cancels the calling task after `delay`, then returns `value`.
    ///
    /// This form is intended for nonthrowing async requirements whose caller
    /// observes cancellation separately from the returned fallback.
    @discardableResult
    public func thenCancel(
        after delay: Duration,
        returning value: Result,
        using clock: any StubClock = StubClocks.continuous
    ) -> CallInteractions {
        let method = requireAsyncRequirement(configuring: "thenCancel")
        guard method.isThrowing == false else {
            preconditionFailure(
                "[TestDoubles] thenCancel(after:returning:) requires a "
                    + "nonthrowing async requirement. Use thenCancel(after:) "
                    + "for a throwing requirement."
            )
        }
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        _ = makeBehaviorChain([
            (
                cancelAfterAnswer(
                    delay,
                    using: clock,
                    outcome: .success(value)
                ),
                .unbounded
            )
        ])
        return interactions
    }
}

extension AsyncClosureCallPattern {
    /// Cancels the caller after a delay, then returns `value`.
    @discardableResult
    public func thenCancel(
        after delay: Duration,
        returning value: Result,
        using clock: any StubClock = StubClocks.continuous
    ) -> CallInteractions {
        base.thenCancel(after: delay, returning: value, using: clock)
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Cancels the caller after a delay, then throws `CancellationError`.
    @discardableResult
    public func thenCancel(
        after delay: Duration,
        using clock: any StubClock = StubClocks.continuous
    ) -> CallInteractions {
        base.thenCancel(after: delay, using: clock)
    }
}

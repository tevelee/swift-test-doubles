extension ThrowingClosureCallPattern {
    /// Computes `times` matching results from the typed input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (Input) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Computes every matching result from the typed input from here on.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Input) throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Computes `times` matching results without reading the input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable () throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Computes every matching result from here on without reading the input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable () throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Computes `times` matching results from a one-based call count and input.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, Input) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from a one-based call count and input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, Input) throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from only a one-based call count.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from only a one-based call count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int) throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Throws `error` for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenThrow(error, times: times)
    }

    /// Throws `error` for every matching invocation from here on.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenThrow(error, times: times)
    }

    /// Configures a finite, inspectable queue of fixed errors.
    public func thenThrowQueue<Failure: Error>(
        _ first: Failure,
        _ rest: Failure...
    ) -> StubBehaviorQueue {
        makeClosureThrowQueue(base: base, first: first, rest: rest)
    }
}

extension AsyncClosureCallPattern {
    /// Immediately computes `times` matching results from the typed input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (Input) -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Immediately computes every matching result from the typed input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Input) -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from the typed input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping (Input) async -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Asynchronously computes every matching result from the typed input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Input) async -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Immediately computes `times` matching results without reading the input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable () -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Immediately computes every matching result without reading the input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable () -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Asynchronously computes `times` matching results without reading the
    /// input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping () async -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Asynchronously computes every matching result without reading the input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping () async -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Computes every matching result from a one-based call count and input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, Input) -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from a one-based call count and input.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, Input) -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from only a one-based call count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int) -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from only a one-based call count.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int) -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes every matching result from a one-based count and
    /// input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int, Input) async -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from a one-based count
    /// and input.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping (Int, Input) async -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes every matching result from only a one-based
    /// call count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int) async -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from only a one-based
    /// call count.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping (Int) async -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Immediately computes `times` matching results from the typed input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (Input) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Immediately computes every matching result from the typed input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Input) throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from the typed input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping (Input) async throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Asynchronously computes every matching result from the typed input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Input) async throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Immediately computes `times` matching results without reading the input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable () throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Immediately computes every matching result without reading the input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable () throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Asynchronously computes `times` matching results without reading the
    /// input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping () async throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Asynchronously computes every matching result without reading the input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping () async throws -> Result
    ) -> CallInteractions {
        base.then(times: times, handler)
    }

    /// Computes every matching result from a one-based call count and input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, Input) throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from a one-based call count and input.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, Input) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from only a one-based call count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int) throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from only a one-based call count.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int) throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes every matching result from a one-based count and
    /// input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int, Input) async throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from a one-based count
    /// and input.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping (Int, Input) async throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes every matching result from only a one-based
    /// call count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int) async throws -> Result
    ) -> CallInteractions {
        base.thenForEachCall(times: times, handler)
    }

    /// Asynchronously computes `times` matching results from only a one-based
    /// call count.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping (Int) async throws -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Throws `error` for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenThrow(error, after: delay, times: times)
    }

    /// Throws `error` for every matching invocation from here on.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenThrow(error, after: delay, times: times)
    }

    /// Throws `error` after a delay measured by `clock`.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration,
        using clock: any StubClock
    ) -> CallInteractions {
        base.thenThrow(error, after: delay, using: clock)
    }

    /// Configures a finite, inspectable queue of fixed errors.
    public func thenThrowQueue<Failure: Error>(
        _ first: Failure,
        _ rest: Failure...
    ) -> StubBehaviorQueue {
        makeClosureThrowQueue(base: base, first: first, rest: rest)
    }
}

extension ThrowingClosureCallPattern where Result == Void {
    /// Completes `times` matching invocations without additional work.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(times: Int = 1) -> StubBehaviorChain<Void> {
        base.thenDoNothing(times: times)
    }

    /// Completes every matching invocation from here on.
    @discardableResult
    public func thenDoNothing(
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenDoNothing(times: times)
    }
}

extension AsyncClosureCallPattern where Result == Void {
    /// Completes `times` matching invocations without additional work.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Void> {
        base.thenDoNothing(after: delay, times: times)
    }

    /// Completes every matching invocation from here on.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenDoNothing(after: delay, times: times)
    }

    /// Waits for cancellation, then completes the invocation.
    @discardableResult
    public func thenAwaitCancellation() -> CallInteractions {
        base.thenAwaitCancellation()
    }
}

extension AsyncThrowingClosureCallPattern where Result == Void {
    /// Completes `times` matching invocations without additional work.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Void> {
        base.thenDoNothing(after: delay, times: times)
    }

    /// Completes every matching invocation from here on.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenDoNothing(after: delay, times: times)
    }
}

private func makeClosureThrowQueue<Result, Failure: Error>(
    base: CallPattern<Result>,
    first: Failure,
    rest: [Failure]
) -> StubBehaviorQueue {
    let method = base.requireOrdinaryResult()
    let errors = [first] + rest
    for error in errors {
        base.requireValidThrownError(error, for: method)
    }
    return base.makeBehaviorChain(
        errors.map { (base.fixedAnswer(.failure($0), after: nil), .exactly(1)) }
    ).behaviorQueue
}

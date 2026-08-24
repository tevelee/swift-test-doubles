extension CallPattern {
    /// Handles `times` matching invocations with a running call count as the
    /// handler's first argument, ahead of the requirement's typed arguments.
    ///
    /// The count starts at 1 and increments once per matching invocation this
    /// behavior serves. Omitting `times:` resolves here when another behavior
    /// follows, making this intermediate behavior exactly once.
    ///
    /// A separate name from `then` keeps the leading count from being mistaken
    /// for the requirement's first argument under trailing-closure syntax.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall<each Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        return makeBehaviorChain([
            (countingImmediateAnswer(handler), .exactly(validatedRepeatCount(times)))
        ])
    }

    /// Handles every matching invocation from here on with a running call count
    /// as the handler's first argument, ahead of the requirement's typed
    /// arguments.
    ///
    /// The count starts at 1 and increments once per matching invocation this
    /// behavior serves. It is the natural way to vary a response by attempt —
    /// fail the first two calls and then recover, say — without threading a
    /// counter through the test yourself:
    ///
    /// ```swift
    /// loader.when { try $0.loadFeed() }.thenForEachCall { attempt in
    ///     if attempt < 3 { throw URLError(.timedOut) }
    ///     return ["Hello, world"]
    /// }
    /// ```
    ///
    /// The count is scoped to this behavior. A later counted behavior starts
    /// again at 1, and a call that matches a more specific registration does
    /// not advance a general fallback's count.
    ///
    /// - Precondition: Handler arguments after the count match a leading prefix
    ///   of the requirement's arguments in type and order. Trailing arguments
    ///   may be omitted, down to a handler taking only the count. A handler
    ///   that throws at runtime requires a throwing requirement.
    @discardableResult
    public func thenForEachCall<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) -> ConfiguredCall<Result> {
        requireOrdinaryResult()
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(countingImmediateAnswer(handler), .unbounded)])
        return configuredCall
    }

    /// Asynchronously handles `times` matching invocations with a running call
    /// count as the handler's first argument. The requirement must be async.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall<each Argument>(
        times: Int = 1,
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        return makeBehaviorChain([
            (countingSuspendingAnswer(handler), .exactly(validatedRepeatCount(times)))
        ])
    }

    /// Asynchronously handles every matching invocation from here on with a
    /// running call count as the handler's first argument. The requirement
    /// must be async.
    @discardableResult
    public func thenForEachCall<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) -> ConfiguredCall<Result> {
        requireOrdinaryResult()
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(countingSuspendingAnswer(handler), .unbounded)])
        return configuredCall
    }
}

extension StubBehaviorChain {
    /// Appends a counted handler for `times` matching invocations.
    ///
    /// The count starts at 1 for this behavior. Omitting `times:` resolves here
    /// when another behavior follows, making this intermediate behavior exactly
    /// once.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall<each Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) -> Self {
        sequence.append(
            countingImmediateAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends a counted handler for every matching invocation from here on.
    @discardableResult
    public func thenForEachCall<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(countingImmediateAnswer(handler), times: .unbounded)
        return configuredCall
    }

    /// Appends an asynchronous counted handler for `times` matching
    /// invocations. The requirement must be async.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall<each Argument>(
        times: Int = 1,
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) -> Self {
        sequence.append(
            countingSuspendingAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends an asynchronous counted handler for every matching invocation
    /// from here on. The requirement must be async.
    @discardableResult
    public func thenForEachCall<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(countingSuspendingAnswer(handler), times: .unbounded)
        return configuredCall
    }
}

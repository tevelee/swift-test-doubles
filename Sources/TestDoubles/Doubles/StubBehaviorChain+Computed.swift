extension StubBehaviorChain {
    /// Appends a handler for `times` matching invocations while preserving an
    /// escaping first argument's concrete closure type.
    @discardableResult
    @_disfavoredOverload
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        times: Int = 1,
        _ handler:
            @escaping @Sendable (
                FirstArgument,
                repeat each AdditionalArgument
            ) throws -> Result
    ) -> Self {
        sequence.append(
            escapingImmediateAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends a handler for every matching invocation from here on while
    /// preserving an escaping first argument's concrete closure type.
    @discardableResult
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping @Sendable (
                FirstArgument,
                repeat each AdditionalArgument
            ) throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(escapingImmediateAnswer(handler), times: .unbounded)
        return configuredCall
    }

    /// Appends an asynchronous handler for `times` matching invocations while
    /// preserving an escaping first argument's concrete closure type.
    @discardableResult
    @_disfavoredOverload
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        times: Int = 1,
        _ handler:
            @escaping (
                FirstArgument,
                repeat each AdditionalArgument
            ) async throws -> Result
    ) -> Self {
        sequence.append(
            escapingSuspendingAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends an asynchronous handler for every matching invocation from here
    /// on while preserving an escaping first argument's concrete closure type.
    @discardableResult
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping (
                FirstArgument,
                repeat each AdditionalArgument
            ) async throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(escapingSuspendingAnswer(handler), times: .unbounded)
        return configuredCall
    }

    /// Appends a handler for `times` matching invocations whose sole argument
    /// needs to preserve its concrete value type.
    @discardableResult
    @_disfavoredOverload
    public func then<Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (Argument) throws -> Result
    ) -> Self {
        sequence.append(
            unaryImmediateAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends a handler for every matching invocation from here on whose sole
    /// argument needs to preserve its concrete value type.
    @discardableResult
    public func then<Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Argument) throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(unaryImmediateAnswer(handler), times: .unbounded)
        return configuredCall
    }

    /// Appends a typed handler for `times` matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func then<each Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> Self {
        sequence.append(
            packedImmediateAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends a typed handler for every matching invocation from here on.
    @discardableResult
    public func then<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(packedImmediateAnswer(handler), times: .unbounded)
        return configuredCall
    }

    /// Appends an asynchronous typed handler for `times` matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func then<each Argument>(
        times: Int = 1,
        _ handler: @escaping (repeat each Argument) async throws -> Result
    ) -> Self {
        sequence.append(
            packedSuspendingAnswer(handler),
            times: .exactly(validatedRepeatCount(times))
        )
        return self
    }

    /// Appends an asynchronous typed handler for every matching invocation
    /// from here on.
    @discardableResult
    public func then<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (repeat each Argument) async throws -> Result
    ) -> ConfiguredCall<Result> {
        validateUnboundedRepeatCount(times)
        sequence.append(packedSuspendingAnswer(handler), times: .unbounded)
        return configuredCall
    }
}

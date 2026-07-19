/// Configures the result of a stubbed method or property.
public struct StubBuilder<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns `value` for the first matching invocation and starts a behavior chain.
    ///
    /// Append more fixed returns or errors to the returned chain to configure
    /// consecutive matching invocations. The final behavior repeats.
    @discardableResult
    public func thenReturn(_ value: Result) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        return makeBehaviorChain([.success(value)])
    }

    /// Returns the listed values to consecutive matching invocations in order,
    /// then keeps returning the final value.
    ///
    /// Each registration consumes its own sequence, so a more specific
    /// registration does not advance a general fallback.
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        return makeBehaviorChain(values.map { .success($0) })
    }

    /// Throws `error` whenever the recorded invocation matches.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure
    ) -> StubBehaviorChain<Result> {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        return makeBehaviorChain([.failure(error)])
    }

    /// Handles a matching invocation whose first argument needs to preserve
    /// its concrete value type, including an escaping closure.
    ///
    /// This overload preserves the argument's escaping convention, which a
    /// closure nested inside a parameter pack cannot currently express.
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        _ handler:
            @escaping @Sendable (
                FirstArgument,
                repeat each AdditionalArgument
            ) throws -> Result
    ) {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            var index = 1
            func nextArgument<T>(_ type: T.Type) -> T {
                defer { index += 1 }
                return typedArgument(
                    type,
                    from: arguments,
                    at: index,
                    method: methodName
                )
            }
            return try handler(
                typedArgument(
                    FirstArgument.self,
                    from: arguments,
                    at: 0,
                    method: methodName
                ),
                repeat nextArgument((each AdditionalArgument).self)
            )
        }
    }

    /// Asynchronously handles a matching invocation whose first argument needs
    /// to preserve its concrete value type, including an escaping closure.
    ///
    /// This overload preserves the argument's escaping convention, which a
    /// closure nested inside a parameter pack cannot currently express.
    public func thenEscaping<FirstArgument, each AdditionalArgument>(
        _ handler:
            @escaping (
                FirstArgument,
                repeat each AdditionalArgument
            ) async throws -> Result
    ) {
        requireOrdinaryResult()
        addAsyncStubBehavior { arguments, methodName in
            var index = 1
            func nextArgument<T>(_ type: T.Type) -> T {
                defer { index += 1 }
                return typedArgument(
                    type,
                    from: arguments,
                    at: index,
                    method: methodName
                )
            }
            return try await handler(
                typedArgument(
                    FirstArgument.self,
                    from: arguments,
                    at: 0,
                    method: methodName
                ),
                repeat nextArgument((each AdditionalArgument).self)
            )
        }
    }

    /// Handles a matching invocation whose sole argument needs to preserve
    /// its concrete value type, including an escaping closure.
    public func then<Argument>(
        _ handler: @escaping @Sendable (Argument) throws -> Result
    ) {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            try handler(
                typedArgument(
                    Argument.self,
                    from: arguments,
                    at: 0,
                    method: methodName
                )
            )
        }
    }

    /// Handles a matching invocation with typed arguments.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. A handler that throws at runtime requires a throwing
    ///   requirement.
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
        }
    }

    /// Handles a matching async invocation with typed arguments.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. The requirement must be async, and a handler that throws at
    ///   runtime requires a throwing requirement.
    ///
    /// The closure intentionally carries its creation actor/executor so an
    /// async stub configured from an actor resumes there. When invoking the
    /// generated existential concurrently, the handler must therefore either
    /// be actor-isolated or protect any mutable captures itself.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Result
    ) {
        requireOrdinaryResult()
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
        }
    }

    @discardableResult
    private func requireOrdinaryResult() -> MethodDescriptor {
        let method = requireRuntimeMethod()
        guard method.kind != .initializer,
            method.returnConvention != .selfType
        else {
            preconditionFailure(
                "[TestDoubles] Configure initializers with when and dynamic Self results with when(returningSelf:)."
            )
        }
        return method
    }

    private func makeBehaviorChain(
        _ results: [StubBehaviorRegistry.FixedResult]
    ) -> StubBehaviorChain<Result> {
        let sequence = recorder.addFixedResultSequence(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            results: results
        )
        return StubBehaviorChain(
            recorder: recorder,
            recording: recording,
            sequence: sequence
        )
    }
}

extension StubBuilder where Result == Void {
    /// Completes a matching invocation without performing additional work.
    @discardableResult
    public func thenDoNothing() -> StubBehaviorChain<Void> {
        thenReturn(())
    }
}

/// Extends a stub registration with fixed behaviors for consecutive invocations.
///
/// Matching invocations consume behaviors in registration order. The final
/// behavior repeats after every earlier behavior has been consumed.
public struct StubBehaviorChain<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall
    let sequence: StubRecorder.ConsumableResults

    /// Appends a fixed return value to the behavior chain.
    @discardableResult
    public func thenReturn(_ value: Result) -> Self {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        sequence.append(.success(value))
        return self
    }

    /// Appends fixed return values to the behavior chain.
    ///
    /// Matching invocations receive the values in order.
    @discardableResult
    public func thenReturn(_ first: Result, _ second: Result, _ rest: Result...) -> Self {
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        sequence.append(contentsOf: values.map { .success($0) })
        return self
    }

    /// Appends a fixed error to the behavior chain.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> Self {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        sequence.append(.failure(error))
        return self
    }
}

/// A behavior chain can cross concurrency domains when its fixed result can.
/// Finish configuring the chain before matching invocations begin.
extension StubBehaviorChain: @unchecked Sendable where Result: Sendable {}

extension StubBehaviorChain where Result == Void {
    /// Appends a no-op behavior to the behavior chain.
    @discardableResult
    public func thenDoNothing() -> Self {
        thenReturn(())
    }
}

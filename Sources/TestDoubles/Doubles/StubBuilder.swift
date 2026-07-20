/// Configures the result of a stubbed method or property.
public struct StubBuilder<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns `value` for the first matching invocation and starts a
    /// behavior chain.
    ///
    /// Append more fixed returns or errors to the returned chain to
    /// configure consecutive matching invocations. With nothing appended
    /// after it, this behavior repeats. Use the `times:` overloads to be
    /// explicit about a bounded or unbounded repeat count instead.
    @discardableResult
    public func thenReturn(_ value: Result) -> StubBehaviorChain<Result> {
        thenReturn(value, times: 1 ... 1)
    }

    /// Returns `value` for `times` consecutive matching invocations, starts a
    /// behavior chain, and requires the chain to be continued or explicitly
    /// discarded.
    ///
    /// `times` counts this behavior's own matching calls, starting at 1 — not
    /// a position in the chain. Append more fixed returns or errors to the
    /// returned chain to configure the calls that follow. A bounded `times`
    /// with nothing appended after it is almost always a mistake — either
    /// keep chaining, or use the unbounded overload (`thenReturn(_:times:)`
    /// with a `PartialRangeFrom`, or the plain `thenReturn(_:)` with no
    /// `times:` at all) if you actually mean "forever."
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(.value(.success(value)), .exactly(count))])
    }

    /// Returns `value` to every matching invocation from here on. This is the
    /// terminal, "and that's it" spelling: nothing can be chained after it.
    public func thenReturn(_ value: Result, times: PartialRangeFrom<Int>) {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(.value(.success(value)), .unbounded)])
    }

    /// Returns the listed values to consecutive matching invocations in order,
    /// then keeps returning the final value.
    ///
    /// Each value here is implicitly one-shot, the same as chaining bare
    /// `thenReturn(_:)` calls for each — this is convenience sugar for
    /// exactly that. There's no `times:` form of this overload: to repeat one
    /// of these values a specific number of times, use `times:` on that
    /// value's own `thenReturn` call instead of listing it out repeatedly or
    /// trying to apply a count across the whole list. Each registration
    /// consumes its own sequence, so a more specific registration does not
    /// advance a general fallback.
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
        return makeBehaviorChain(values.map { (.value(.success($0)), .exactly(1)) })
    }

    /// Throws `error` whenever the recorded invocation matches.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// With nothing appended after it, this behavior repeats. Use the
    /// `times:` overloads to be explicit about a bounded or unbounded repeat
    /// count instead.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> StubBehaviorChain<Result> {
        thenThrow(error, times: 1 ... 1)
    }

    /// Throws `error` for `times` consecutive matching invocations, and
    /// requires the returned chain to be continued or explicitly discarded.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// `times` counts this behavior's own matching calls, starting at 1 — not
    /// a position in the chain. A bounded `times` with nothing appended after
    /// it is almost always a mistake — either keep chaining, or use the
    /// unbounded overload (`thenThrow(_:times:)` with a `PartialRangeFrom`,
    /// or the plain `thenThrow(_:)` with no `times:` at all) if you actually
    /// mean "forever."
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: ClosedRange<Int>
    ) -> StubBehaviorChain<Result> {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(.value(.failure(error)), .exactly(count))])
    }

    /// Throws `error` to every matching invocation from here on. This is the
    /// terminal, "and that's it" spelling: nothing can be chained after it.
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: PartialRangeFrom<Int>
    ) {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(.value(.failure(error)), .unbounded)])
    }

    /// Halts the process with an actionable diagnostic for every matching
    /// invocation from here on, instead of returning or throwing. This is
    /// terminal, like the unbounded `thenReturn`/`thenThrow`: nothing can be
    /// chained after it.
    ///
    /// Use this to turn an overrun — a call count you didn't account for —
    /// into a hard failure instead of letting the preceding behavior repeat.
    /// The diagnostic reports the method, its arguments, and every registered
    /// stub, the same as an unstubbed call; `message` is an optional
    /// addendum explaining why this call is unexpected.
    public func thenFatalError(_ message: String? = nil) {
        requireOrdinaryResult()
        _ = makeBehaviorChain([(.fatal(message: message), .unbounded)])
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
        _ answers: [(StubRecorder.QueuedAnswer, StubRecorder.RepeatCount)]
    ) -> StubBehaviorChain<Result> {
        let sequence = recorder.addFixedResultSequence(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            answers: answers
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
    /// With nothing appended after it, this behavior repeats.
    @discardableResult
    public func thenDoNothing() -> StubBehaviorChain<Void> {
        thenReturn((), times: 1 ... 1)
    }

    /// Completes `times` consecutive matching invocations without performing
    /// additional work, and requires the returned chain to be continued or
    /// explicitly discarded.
    public func thenDoNothing(times: ClosedRange<Int>) -> StubBehaviorChain<Void> {
        thenReturn((), times: times)
    }

    /// Completes every matching invocation without performing additional
    /// work, from here on. This is terminal — nothing can be chained after it.
    public func thenDoNothing(times: PartialRangeFrom<Int>) {
        thenReturn((), times: times)
    }
}

/// `times:` always counts a behavior's own matching calls starting at 1, not
/// a position in the chain — so a flat default is correct at every position.
private func validatedRepeatCount(_ times: ClosedRange<Int>) -> Int {
    precondition(
        times.lowerBound == 1,
        "[TestDoubles] times: must start at 1; it counts this behavior's own "
            + "matching calls, not a position in the chain."
    )
    return times.upperBound
}

private func validateUnboundedRepeatCount(_ times: PartialRangeFrom<Int>) {
    precondition(
        times.lowerBound == 1,
        "[TestDoubles] times: must start at 1; it counts this behavior's own "
            + "matching calls, not a position in the chain."
    )
}

/// Extends a stub registration with fixed behaviors for consecutive invocations.
///
/// Matching invocations consume behaviors in registration order. A behavior
/// with nothing appended after it keeps repeating once its own `times` range
/// is consumed, whether that range was bounded or unbounded — use
/// ``thenFatalError(_:)`` to make an overrun a hard failure instead.
public struct StubBehaviorChain<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall
    let sequence: StubRecorder.ConsumableResults

    /// Appends a fixed return value to the behavior chain.
    ///
    /// With nothing appended after it, this behavior repeats. Use the
    /// `times:` overloads to be explicit about a bounded or unbounded repeat
    /// count instead.
    @discardableResult
    public func thenReturn(_ value: Result) -> Self {
        thenReturn(value, times: 1 ... 1)
    }

    /// Appends a fixed return value for `times` consecutive matching
    /// invocations, and requires the chain to be continued or explicitly
    /// discarded.
    ///
    /// A bounded `times` with nothing appended after it is almost always a
    /// mistake — either keep chaining, or use the unbounded overload
    /// (`thenReturn(_:times:)` with a `PartialRangeFrom`, or the plain
    /// `thenReturn(_:)` with no `times:` at all) if you actually mean
    /// "forever."
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) -> Self {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        sequence.append(.value(.success(value)), times: .exactly(count))
        return self
    }

    /// Appends a fixed return value for every matching invocation from here
    /// on. This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected.
    public func thenReturn(_ value: Result, times: PartialRangeFrom<Int>) {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        sequence.append(.value(.success(value)), times: .unbounded)
    }

    /// Appends fixed return values to the behavior chain.
    ///
    /// Matching invocations receive the values in order. Each value here is
    /// implicitly one-shot, the same as appending bare `thenReturn(_:)` calls
    /// for each. There's no `times:` form of this overload — to repeat one of
    /// these values a specific number of times, use `times:` on that value's
    /// own `thenReturn` call instead.
    @discardableResult
    public func thenReturn(_ first: Result, _ second: Result, _ rest: Result...) -> Self {
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        sequence.append(contentsOf: values.map { .value(.success($0)) })
        return self
    }

    /// Appends a fixed error to the behavior chain.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// With nothing appended after it, this behavior repeats. Use the
    /// `times:` overloads to be explicit about a bounded or unbounded repeat
    /// count instead.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> Self {
        thenThrow(error, times: 1 ... 1)
    }

    /// Appends a fixed error for `times` consecutive matching invocations,
    /// and requires the chain to be continued or explicitly discarded.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// A bounded `times` with nothing appended after it is almost always a
    /// mistake — either keep chaining, or use the unbounded overload
    /// (`thenThrow(_:times:)` with a `PartialRangeFrom`, or the plain
    /// `thenThrow(_:)` with no `times:` at all) if you actually mean
    /// "forever."
    public func thenThrow<Failure: Error>(_ error: Failure, times: ClosedRange<Int>) -> Self {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        sequence.append(.value(.failure(error)), times: .exactly(count))
        return self
    }

    /// Appends a fixed error for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected.
    public func thenThrow<Failure: Error>(_ error: Failure, times: PartialRangeFrom<Int>) {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        validateUnboundedRepeatCount(times)
        sequence.append(.value(.failure(error)), times: .unbounded)
    }

    /// Halts the process with an actionable diagnostic for every matching
    /// invocation from here on, instead of returning or throwing. This is
    /// terminal, like the unbounded `thenReturn`/`thenThrow`. See
    /// ``StubBuilder/thenFatalError(_:)``.
    public func thenFatalError(_ message: String? = nil) {
        sequence.append(.fatal(message: message), times: .unbounded)
    }
}

/// A behavior chain can cross concurrency domains when its fixed result can.
/// Finish configuring the chain before matching invocations begin.
extension StubBehaviorChain: @unchecked Sendable where Result: Sendable {}

extension StubBehaviorChain where Result == Void {
    /// Appends a no-op behavior to the behavior chain. With nothing appended
    /// after it, this behavior repeats.
    @discardableResult
    public func thenDoNothing() -> Self {
        thenReturn((), times: 1 ... 1)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations,
    /// and requires the chain to be continued or explicitly discarded.
    public func thenDoNothing(times: ClosedRange<Int>) -> Self {
        thenReturn((), times: times)
    }

    /// Appends a no-op behavior for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it.
    public func thenDoNothing(times: PartialRangeFrom<Int>) {
        thenReturn((), times: times)
    }
}

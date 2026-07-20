/// Configures the result of a stubbed method or property.
public struct StubBuilder<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall

    // MARK: - thenReturn

    // `times:` selects one of three shapes for a fixed-return behavior, and
    // which one you get without writing `times:` at all depends on whether
    // you keep chaining:
    //
    //   .thenReturn(x)                      // bare — see below
    //   .thenReturn(x, times: 1...3)        // explicit bounded
    //   .thenReturn(x, times: 1...)         // explicit unbounded
    //   .thenReturn(x, times: 3)            // explicit bounded, shorthand for 1...3
    //
    // The bounded shape returns a `StubBehaviorChain` so more behaviors can
    // be appended; the unbounded shape returns `Void`, since nothing
    // sensible can follow "every call from here on." Each pair below shares
    // one parameter list and differs only in return type, with the
    // chain-returning half marked `@_disfavoredOverload`. That lets the
    // compiler pick between them using how the call is actually used:
    // standalone (result discarded) resolves to the `Void` half; chained
    // (`.thenReturn(x).thenThrow(y)`) can only type-check against the
    // `StubBehaviorChain` half, so that's the one selected even though it's
    // disfavored. The same trick makes the *bare* call position-sensitive:
    // it's really `times: Int = 1`, competing against `times:
    // PartialRangeFrom<Int> = 1...`, so a bare call left standalone resolves
    // to "1 shot, then repeat forever" and a bare call that's chained
    // further resolves to "exactly 1, then advance" — matching what most
    // Mockito-style chains want without spelling out `times:` at all.
    //
    // A bounded run that reaches the end of the chain with nothing after it
    // is not the same as unbounded: it fails with a diagnostic once its
    // count is exceeded, rather than repeating. If you want a value to
    // repeat forever, say so with an unbounded `times:` (or the bare form,
    // which defaults there when nothing follows) — a bounded count means
    // exactly that many, and no more.

    /// Returns `value` for the first matching invocation and starts a
    /// behavior chain.
    ///
    /// With nothing chained after it, this behaves like `times: 1...`
    /// (repeats forever). Append more behaviors to the returned chain to
    /// configure the calls that follow instead.
    @_disfavoredOverload
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(.value(.success(value)), .exactly(count))])
    }

    /// Returns `value` for `times` consecutive matching invocations, and
    /// requires the returned chain to be continued or explicitly discarded.
    ///
    /// `times` counts this behavior's own matching calls, starting at 1 —
    /// not a position in the chain. With nothing appended after it, a call
    /// beyond `times` fails with a diagnostic instead of repeating `value`;
    /// use the unbounded overload (`times:` with a `PartialRangeFrom`, or
    /// the bare `thenReturn(_:)` left standalone) if you want `value` to
    /// keep repeating instead.
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        _ = makeBehaviorChain([(.value(.success(value)), .exactly(count))])
    }

    /// Returns `value` for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenReturn(_ value: Result, times: Int = 1) -> StubBehaviorChain<Result> {
        thenReturn(value, times: validatedRepeatRange(times: times))
    }

    /// Returns `value` for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    public func thenReturn(_ value: Result, times: Int) {
        thenReturn(value, times: validatedRepeatRange(times: times))
    }

    /// Returns `value` to every matching invocation from here on. This is
    /// terminal: nothing can be chained after it.
    ///
    /// Omitting `times:` entirely also resolves here whenever nothing
    /// follows, so a plain `stub.when { ... }.thenReturn(x)` with no further
    /// configuration means "always return x" — the common case for a
    /// single-behavior stub.
    public func thenReturn(_ value: Result, times: PartialRangeFrom<Int> = 1...) {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(.value(.success(value)), .unbounded)])
    }

    /// Returns the listed values to consecutive matching invocations in
    /// order, then keeps returning the final value forever. This is
    /// terminal: nothing can be chained after it, since its last entry is
    /// always unbounded.
    ///
    /// Each value here is implicitly one-shot except the last, which is
    /// unbounded — the same as chaining bare `thenReturn(_:)` calls for
    /// each. There's no `times:` form of this overload: to repeat one of
    /// these values a specific number of times, use `times:` on that
    /// value's own `thenReturn` call instead of listing it out repeatedly or
    /// trying to apply a count across the whole list. Each registration
    /// consumes its own sequence, so a more specific registration does not
    /// advance a general fallback.
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) {
        requireOrdinaryResult()
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        _ = makeBehaviorChain(
            values.dropLast().map { (.value(.success($0)), .exactly(1)) }
                + [(.value(.success(rest.last ?? second)), .unbounded)]
        )
    }

    // MARK: - thenThrow

    /// Throws `error` whenever the recorded invocation matches, and starts a
    /// behavior chain.
    ///
    /// The recorded requirement must be throwing. For a concrete
    /// typed-throws requirement, `error` must be compatible with its
    /// declared error type. With nothing chained after it, this behaves like
    /// `times: 1...` (repeats forever). `times:` selects between a bounded
    /// count, an unbounded repeat, and — left bare — whichever of those fits
    /// where this call sits in the chain; see `thenReturn(_:times:)` for the
    /// full explanation, which applies here identically.
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: ClosedRange<Int>
    ) -> StubBehaviorChain<Result> {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(.value(.failure(error)), .exactly(count))])
    }

    /// Throws `error` for `times` consecutive matching invocations, and
    /// requires the returned chain to be continued or explicitly discarded.
    ///
    /// The recorded requirement must be throwing. For a concrete
    /// typed-throws requirement, `error` must be compatible with its
    /// declared error type. `times` counts this behavior's own matching
    /// calls, starting at 1 — not a position in the chain. With nothing
    /// appended after it, a call beyond `times` fails with a diagnostic
    /// instead of repeating `error`.
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: ClosedRange<Int>
    ) {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        _ = makeBehaviorChain([(.value(.failure(error)), .exactly(count))])
    }

    /// Throws `error` for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(_ error: Failure, times: Int = 1) -> StubBehaviorChain<Result> {
        thenThrow(error, times: validatedRepeatRange(times: times))
    }

    /// Throws `error` for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    public func thenThrow<Failure: Error>(_ error: Failure, times: Int) {
        thenThrow(error, times: validatedRepeatRange(times: times))
    }

    /// Throws `error` to every matching invocation from here on. This is
    /// terminal: nothing can be chained after it.
    ///
    /// Omitting `times:` entirely also resolves here whenever nothing
    /// follows, so a plain `stub.when { ... }.thenThrow(x)` with no further
    /// configuration means "always throw x."
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        times: PartialRangeFrom<Int> = 1...
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
    /// Completes a matching invocation without performing additional work,
    /// and starts a behavior chain.
    ///
    /// With nothing chained after it, this behaves like `times: 1...`
    /// (repeats forever).
    @_disfavoredOverload
    public func thenDoNothing(times: ClosedRange<Int>) -> StubBehaviorChain<Void> {
        thenReturn((), times: times)
    }

    /// Completes `times` consecutive matching invocations without performing
    /// additional work, and requires the returned chain to be continued or
    /// explicitly discarded.
    public func thenDoNothing(times: ClosedRange<Int>) {
        thenReturn((), times: times)
    }

    /// Completes `times` consecutive matching invocations without performing
    /// additional work. Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenDoNothing(times: Int = 1) -> StubBehaviorChain<Void> {
        thenReturn((), times: times)
    }

    /// Completes `times` consecutive matching invocations without performing
    /// additional work. Shorthand for `times: 1...times`.
    public func thenDoNothing(times: Int) {
        thenReturn((), times: times)
    }

    /// Completes every matching invocation without performing additional
    /// work, from here on. This is terminal — nothing can be chained after it.
    public func thenDoNothing(times: PartialRangeFrom<Int> = 1...) {
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

/// Validates a plain `times: Int` shorthand count and expands it to the
/// `1...times` range the `ClosedRange` overloads expect. Constructing that
/// range directly would trap inside `ClosedRange` itself for `times < 1`,
/// bypassing this library's own diagnostic — so the count is checked first.
private func validatedRepeatRange(times: Int) -> ClosedRange<Int> {
    precondition(
        times >= 1,
        "[TestDoubles] times: must be at least 1; it counts this behavior's own "
            + "matching calls, not a position in the chain."
    )
    return 1 ... times
}

/// Extends a stub registration with fixed behaviors for consecutive
/// invocations.
///
/// Matching invocations consume behaviors in registration order. A bounded
/// run left terminal (nothing appended after it) fails with a diagnostic
/// once its own count is exceeded; an unbounded run keeps repeating. See
/// `StubBuilder.thenReturn(_:times:)` for how `times:` selects between the
/// two, and the bare form, at each position.
public struct StubBehaviorChain<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall
    let sequence: StubRecorder.ConsumableResults

    /// Appends a fixed return value to the behavior chain.
    ///
    /// With nothing appended after it, this behaves like `times: 1...`
    /// (repeats forever).
    @_disfavoredOverload
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) -> Self {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        sequence.append(.value(.success(value)), times: .exactly(count))
        return self
    }

    /// Appends a fixed return value for `times` consecutive matching
    /// invocations, and requires the chain to be continued or explicitly
    /// discarded.
    ///
    /// With nothing appended after it, a call beyond `times` fails with a
    /// diagnostic instead of repeating `value`.
    public func thenReturn(_ value: Result, times: ClosedRange<Int>) {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        sequence.append(.value(.success(value)), times: .exactly(count))
    }

    /// Appends a fixed return value for `times` consecutive matching
    /// invocations. Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenReturn(_ value: Result, times: Int = 1) -> Self {
        thenReturn(value, times: validatedRepeatRange(times: times))
    }

    /// Appends a fixed return value for `times` consecutive matching
    /// invocations. Shorthand for `times: 1...times`.
    public func thenReturn(_ value: Result, times: Int) {
        thenReturn(value, times: validatedRepeatRange(times: times))
    }

    /// Appends a fixed return value for every matching invocation from here
    /// on. This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected.
    public func thenReturn(_ value: Result, times: PartialRangeFrom<Int> = 1...) {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        sequence.append(.value(.success(value)), times: .unbounded)
    }

    /// Appends fixed return values to the behavior chain, in order, then
    /// keeps returning the final value forever. This is terminal: nothing
    /// can be chained after it, since its last entry is always unbounded.
    ///
    /// Each value here is implicitly one-shot except the last, which is
    /// unbounded — the same as appending bare `thenReturn(_:)` calls for
    /// each. There's no `times:` form of this overload — to repeat one of
    /// these values a specific number of times, use `times:` on that value's
    /// own `thenReturn` call instead.
    public func thenReturn(_ first: Result, _ second: Result, _ rest: Result...) {
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        sequence.append(contentsOf: values.dropLast().map { .value(.success($0)) })
        sequence.append(.value(.success(rest.last ?? second)), times: .unbounded)
    }

    /// Appends a fixed error to the behavior chain.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// With nothing appended after it, this behaves like `times: 1...`
    /// (repeats forever).
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(_ error: Failure, times: ClosedRange<Int>) -> Self {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        sequence.append(.value(.failure(error)), times: .exactly(count))
        return self
    }

    /// Appends a fixed error for `times` consecutive matching invocations,
    /// and requires the chain to be continued or explicitly discarded.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// With nothing appended after it, a call beyond `times` fails with a
    /// diagnostic instead of repeating `error`.
    public func thenThrow<Failure: Error>(_ error: Failure, times: ClosedRange<Int>) {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        sequence.append(.value(.failure(error)), times: .exactly(count))
    }

    /// Appends a fixed error for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(_ error: Failure, times: Int = 1) -> Self {
        thenThrow(error, times: validatedRepeatRange(times: times))
    }

    /// Appends a fixed error for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    public func thenThrow<Failure: Error>(_ error: Failure, times: Int) {
        thenThrow(error, times: validatedRepeatRange(times: times))
    }

    /// Appends a fixed error for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected.
    public func thenThrow<Failure: Error>(_ error: Failure, times: PartialRangeFrom<Int> = 1...) {
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
    /// after it, this behaves like `times: 1...` (repeats forever).
    @_disfavoredOverload
    public func thenDoNothing(times: ClosedRange<Int>) -> Self {
        thenReturn((), times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations,
    /// and requires the chain to be continued or explicitly discarded.
    public func thenDoNothing(times: ClosedRange<Int>) {
        thenReturn((), times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    @_disfavoredOverload
    public func thenDoNothing(times: Int = 1) -> Self {
        thenReturn((), times: times)
    }

    /// Appends a no-op behavior for `times` consecutive matching invocations.
    /// Shorthand for `times: 1...times`.
    public func thenDoNothing(times: Int) {
        thenReturn((), times: times)
    }

    /// Appends a no-op behavior for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it.
    public func thenDoNothing(times: PartialRangeFrom<Int> = 1...) {
        thenReturn((), times: times)
    }
}

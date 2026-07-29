import InternalRuntimeContract

/// A reusable description of one method, property, subscript, static member,
/// or initializer call.
///
/// Create a pattern with `when`, then use the same value to configure its
/// behavior, verify its call count, read prior arguments, or observe future
/// calls. Matchers remain attached to the pattern, so the invocation only
/// needs to be described once.
public struct CallPattern<Result>: Sendable {
    let recorder: StubRecorder
    let recording: RecordedCall

    // MARK: - thenReturn

    // `times:` selects one of two shapes for a fixed-return behavior, and
    // which one you get without writing `times:` at all depends on whether
    // you keep chaining:
    //
    //   .thenReturn(x)               // bare — see below
    //   .thenReturn(x, times: 3)     // explicit bounded
    //   .thenReturn(x, times: 1...)  // explicit unbounded
    //
    // The bounded shape returns a `StubBehaviorChain` so more behaviors can
    // be appended; the unbounded shape returns `CallInteractions`, since
    // another behavior cannot sensibly follow "every call from here on," but
    // the configured call should remain available for verification and
    // inspection. The bounded overload is marked `@_disfavoredOverload`.
    // That makes a bare call position-sensitive: left terminal it resolves to
    // the unbounded interaction handle, while a following `.then...` forces
    // the bounded chain overload and makes the answer one-shot.
    //
    // A bounded run that reaches the end of the chain with nothing after it
    // is not the same as unbounded: it fails with a diagnostic once its
    // count is exceeded, rather than repeating. If you want a value to
    // repeat forever, say so with an unbounded `times:` (or the bare form,
    // which defaults there when nothing follows) — a bounded count means
    // exactly that many, and no more.

    /// Returns `value` for `times` consecutive matching invocations.
    ///
    /// `times` counts this behavior's own matching calls. A later behavior in
    /// the chain takes over after exactly that many calls. `after:` delays
    /// delivery and requires an async requirement.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(fixedAnswer(.success(value), after: delay), .exactly(count))])
    }

    /// Returns `value` to every matching invocation from here on. This is
    /// terminal: the returned handle supports interaction operations but no
    /// further behavior can be chained after it.
    ///
    /// Omitting `times:` entirely also resolves here whenever nothing
    /// follows, so a plain `stub.when { ... }.thenReturn(x)` with no further
    /// configuration means "always return x" — the common case for a
    /// single-behavior stub.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(fixedAnswer(.success(value), after: delay), .unbounded)])
        return interactions
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
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> CallInteractions {
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
        return interactions
    }

    // MARK: - thenThrow

    /// Throws `error` for `times` consecutive matching invocations.
    ///
    /// The recorded requirement must be throwing. For a concrete
    /// typed-throws requirement, `error` must be compatible with its declared
    /// error type.
    ///
    /// A later behavior in the chain takes over after exactly that many
    /// matching calls.
    @discardableResult
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        return makeBehaviorChain([(fixedAnswer(.failure(error), after: delay), .exactly(count))])
    }

    /// Throws `error` to every matching invocation from here on. This is
    /// terminal: nothing can be chained after it.
    ///
    /// Omitting `times:` entirely also resolves here whenever nothing
    /// follows, so a plain `stub.when { ... }.thenThrow(x)` with no further
    /// configuration means "always throw x."
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        validateUnboundedRepeatCount(times)
        _ = makeBehaviorChain([(fixedAnswer(.failure(error), after: delay), .unbounded)])
        return interactions
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
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> CallInteractions {
        requireOrdinaryResult()
        _ = makeBehaviorChain([(.fatal(message: message), .unbounded)])
        return interactions
    }

    /// Parks every matching invocation from here on, never completing it, to
    /// model a dependency that has wedged. This is terminal, like the
    /// unbounded `thenReturn`/`thenThrow`: nothing can be chained after it.
    ///
    /// The requirement must be async. A parked call stays suspended even if
    /// its task is cancelled — reacting to cancellation is
    /// `thenAwaitCancellation`'s contract — so drive it from a task the test
    /// does not await, and pair it with the timeout path under test. The
    /// invocation is recorded before parking, so verification (including
    /// `verify(_:within:)`) observes calls that never complete.
    public func thenNeverReturn() {
        requireOrdinaryResult()
        _ = makeBehaviorChain([(neverAnswer(), .unbounded)])
    }

    /// Forwards every matching invocation from here on to the spy's real
    /// target, as if no registration had matched. This is terminal, like the
    /// unbounded `thenReturn`/`thenThrow`: nothing can be chained after it.
    ///
    /// Only a `Spy` can forward. Under first-match-wins, a standalone
    /// `thenForward()` registered before a broader override punches a hole
    /// through it, keeping the real behavior for the arguments it matches.
    /// At the end of a chain it hands the remaining calls back to the live
    /// implementation, such as failing twice and then recovering for real.
    /// Forwarded calls are recorded and verifiable like any other.
    public func thenForward() {
        requireOrdinaryResult()
        _ = makeBehaviorChain([(forwardAnswer(), .unbounded)])
    }

    /// Parks every matching invocation from here on and hands control to the
    /// returned suspension: the test awaits the call's arrival with
    /// `waitForCall(count:)`, asserts whatever must hold while the call is in
    /// flight, then completes it with `resume(returning:)` or
    /// `resume(throwing:)`. Parked calls resume in arrival order. This is
    /// terminal, like the unbounded `thenReturn`/`thenThrow`: nothing can be
    /// chained after it.
    ///
    /// The requirement must be async. A parked call stays suspended even if
    /// its task is cancelled; the suspension is the only thing that completes
    /// it. Resuming with no call parked is a test bug and halts with a
    /// diagnostic. The invocation is recorded before parking, so verification
    /// observes calls still in flight.
    public func thenSuspend() -> StubSuspension<Result> {
        let method = requireOrdinaryResult()
        requireAsyncRequirement(configuring: "thenSuspend")
        let suspension = StubSuspension<Result>(recorder: recorder, method: method)
        TestDoubleTestingContext.session?.register(
            TestDoubleTeardownCheck(kind: .suspension) { [weak suspension] in
                suspension?.teardownDiagnostic()
            }
        )
        addAsyncStubBehavior { _, _ in
            try await suspension.park()
        }
        return suspension
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then completes it the way a well-behaved dependency would:
    /// a throwing requirement throws `CancellationError`, and a non-throwing
    /// `Void` requirement returns. A non-throwing requirement with a result
    /// has no implicit outcome; use `thenAwaitCancellation(returning:)`. This
    /// is terminal, like the unbounded `thenReturn`/`thenThrow`.
    ///
    /// The requirement must be async. A call whose task is already cancelled
    /// completes immediately, and the invocation is recorded before parking,
    /// so verification observes calls still awaiting cancellation.
    public func thenAwaitCancellation() {
        requireOrdinaryResult()
        requireImplicitCancellationOutcome(returning: Result.self)
        _ = makeBehaviorChain([(awaitCancellationAnswer(nil), .unbounded)])
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then completes it with `value`. This is terminal, like the
    /// unbounded `thenReturn`/`thenThrow`. See
    /// ``CallPattern/thenAwaitCancellation()`` for the full contract.
    public func thenAwaitCancellation(returning value: Result) {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        _ = makeBehaviorChain([(awaitCancellationAnswer(.success(value)), .unbounded)])
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then throws `error`. This is terminal, like the unbounded
    /// `thenReturn`/`thenThrow`. See ``CallPattern/thenAwaitCancellation()``
    /// for the full contract.
    public func thenAwaitCancellation<Failure: Error>(throwing error: Failure) {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        _ = makeBehaviorChain([(awaitCancellationAnswer(.failure(error)), .unbounded)])
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
    func requireOrdinaryResult() -> RuntimeMethod {
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

    func makeBehaviorChain(
        _ answers: [(StubRecorder.QueuedAnswer, StubRecorder.RepeatCount)]
    ) -> StubBehaviorChain<Result> {
        let sequence = recorder.addFixedResultSequence(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            location: recording.registrationLocation,
            answers: answers
        )
        return StubBehaviorChain(
            recorder: recorder,
            recording: recording,
            sequence: sequence,
            behaviorQueue: StubBehaviorQueue(
                sequence: sequence,
                recorder: recorder,
                requirementName: recording.name
            )
        )
    }

    /// Configures a finite, inspectable queue of fixed return values.
    ///
    /// Unlike the multi-value `thenReturn` overload, this queue has no
    /// repeating final value: an extra matching call fails, and
    /// ``StubBehaviorQueue`` can assert that every queued answer was used.
    public func thenQueue(_ first: Result, _ rest: Result...) -> StubBehaviorQueue {
        let values = [first] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(value, for: recording.methodIndex)
        }
        return makeBehaviorChain(
            values.map { (fixedAnswer(.success($0), after: nil), .exactly(1)) }
        ).behaviorQueue
    }

    /// Returns `value` after `delay` measured by `clock` for every matching
    /// invocation. Use ``ManualStubClock`` to advance time deterministically.
    public func thenReturn(
        _ value: Result,
        after delay: Duration,
        using clock: any StubClock
    ) {
        requireOrdinaryResult()
        recorder.requireReturnValueMatchesRuntimeType(value, for: recording.methodIndex)
        _ = makeBehaviorChain([
            (fixedAnswer(.success(value), after: delay, using: clock), .unbounded)
        ])
    }

    /// Throws `error` after `delay` measured by `clock` for every matching
    /// invocation.
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration,
        using clock: any StubClock
    ) {
        let method = requireOrdinaryResult()
        requireValidThrownError(error, for: method)
        _ = makeBehaviorChain([
            (fixedAnswer(.failure(error), after: delay, using: clock), .unbounded)
        ])
    }

    /// Configures a finite, inspectable queue of errors.
    public func thenThrowQueue<Failure: Error>(
        _ first: Failure,
        _ rest: Failure...
    ) -> StubBehaviorQueue {
        let method = requireOrdinaryResult()
        let errors = [first] + rest
        for error in errors {
            requireValidThrownError(error, for: method)
        }
        return makeBehaviorChain(
            errors.map { (fixedAnswer(.failure($0), after: nil), .exactly(1)) }
        ).behaviorQueue
    }
}

extension CallPattern where Result == Void {
    /// Completes `times` consecutive matching invocations without performing
    /// additional work.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Void> {
        thenReturn((), after: delay, times: times)
    }

    /// Completes every matching invocation without performing additional
    /// work.
    ///
    /// The returned handle supports interaction operations but no further
    /// behavior can be chained after it. Omitting `times:` resolves here when
    /// this is the trailing behavior; an intermediate bare `thenDoNothing()`
    /// instead completes exactly one invocation.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        thenReturn((), after: delay, times: times)
    }
}

/// `times:` counts a behavior's own matching calls, not a position in the
/// chain.
private func validatedRepeatCount(_ times: Int) -> Int {
    guard times >= 1 else {
        fatalError(
            "[TestDoubles] times: must be at least 1; it counts this behavior's own "
                + "matching calls, not a position in the chain."
        )
    }
    return times
}

private func validateUnboundedRepeatCount(_ times: PartialRangeFrom<Int>) {
    guard times.lowerBound == 1 else {
        fatalError(
            "[TestDoubles] times: must start at 1; it counts this behavior's own "
                + "matching calls, not a position in the chain."
        )
    }
}

/// Extends a stub registration with fixed behaviors for consecutive
/// invocations.
///
/// Matching invocations consume behaviors in registration order. A bare
/// intermediate behavior runs exactly once, while a bare trailing behavior
/// repeats without bound. An explicitly bounded run left terminal (nothing
/// appended after it) fails with a diagnostic once its own count is exceeded.
/// See `CallPattern.thenReturn(_:times:)` for how `times:` selects between
/// the bounded and unbounded forms.
public struct StubBehaviorChain<Result> {
    let recorder: StubRecorder
    let recording: RecordedCall
    let sequence: StubRecorder.ConsumableResults
    /// An inspectable view of this registration's queued fixed behaviors.
    public let behaviorQueue: StubBehaviorQueue

    /// An observation-only view of invocations matching this chain's call.
    public var interactions: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording)
    }

    /// Appends a fixed return value for `times` consecutive matching
    /// invocations.
    ///
    /// A later behavior takes over after exactly that many matching calls.
    /// `after:` delays delivery and requires an async requirement. Omitting
    /// `times:` resolves here when another behavior follows, making this
    /// intermediate behavior exactly once.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> Self {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        let count = validatedRepeatCount(times)
        sequence.append(fixedAnswer(.success(value), after: delay), times: .exactly(count))
        return self
    }

    /// Appends a fixed return value for every matching invocation from here
    /// on. This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected. Omitting `times:`
    /// resolves here when this is the trailing behavior.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        validateUnboundedRepeatCount(times)
        sequence.append(fixedAnswer(.success(value), after: delay), times: .unbounded)
        return interactions
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
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> CallInteractions {
        let values = [first, second] + rest
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(
                value,
                for: recording.methodIndex
            )
        }
        sequence.append(contentsOf: values.dropLast().map { .value(.success($0)) })
        sequence.append(.value(.success(rest.last ?? second)), times: .unbounded)
        return interactions
    }

    /// Appends a fixed error for `times` consecutive matching invocations.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    /// Omitting `times:` resolves here when another behavior follows, making
    /// this intermediate behavior exactly once.
    @discardableResult
    @_disfavoredOverload
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> Self {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        let count = validatedRepeatCount(times)
        sequence.append(fixedAnswer(.failure(error), after: delay), times: .exactly(count))
        return self
    }

    /// Appends a fixed error for every matching invocation from here on.
    /// This is terminal — nothing can be chained after it — and anything
    /// already appended earlier in the chain is unaffected. Omitting `times:`
    /// resolves here when this is the trailing behavior.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        validateUnboundedRepeatCount(times)
        sequence.append(fixedAnswer(.failure(error), after: delay), times: .unbounded)
        return interactions
    }

    /// Halts the process with an actionable diagnostic for every matching
    /// invocation from here on, instead of returning or throwing. This is
    /// terminal, like the unbounded `thenReturn`/`thenThrow`. See
    /// ``CallPattern/thenFatalError(_:)``.
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> CallInteractions {
        sequence.append(.fatal(message: message), times: .unbounded)
        return interactions
    }

    /// Parks every matching invocation from here on, never completing it.
    /// This is terminal, like the unbounded `thenReturn`/`thenThrow`. See
    /// ``CallPattern/thenNeverReturn()`` for the full contract.
    public func thenNeverReturn() {
        sequence.append(neverAnswer(), times: .unbounded)
    }

    /// Forwards every matching invocation from here on to the spy's real
    /// target. This is terminal, like the unbounded `thenReturn`/`thenThrow`.
    /// See ``CallPattern/thenForward()`` for the full contract.
    public func thenForward() {
        sequence.append(forwardAnswer(), times: .unbounded)
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then completes it with the requirement's implicit outcome.
    /// This is terminal, like the unbounded `thenReturn`/`thenThrow`. See
    /// ``CallPattern/thenAwaitCancellation()`` for the full contract.
    public func thenAwaitCancellation() {
        requireImplicitCancellationOutcome(returning: Result.self)
        sequence.append(awaitCancellationAnswer(nil), times: .unbounded)
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then completes it with `value`. This is terminal, like the
    /// unbounded `thenReturn`/`thenThrow`. See
    /// ``CallPattern/thenAwaitCancellation()`` for the full contract.
    public func thenAwaitCancellation(returning value: Result) {
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        sequence.append(awaitCancellationAnswer(.success(value)), times: .unbounded)
    }

    /// Parks every matching invocation from here on until its task is
    /// cancelled, then throws `error`. This is terminal, like the unbounded
    /// `thenReturn`/`thenThrow`. See ``CallPattern/thenAwaitCancellation()``
    /// for the full contract.
    public func thenAwaitCancellation<Failure: Error>(throwing error: Failure) {
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        sequence.append(awaitCancellationAnswer(.failure(error)), times: .unbounded)
    }
}

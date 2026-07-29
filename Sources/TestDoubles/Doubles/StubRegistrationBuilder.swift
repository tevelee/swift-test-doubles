import InternalRuntimeContract

protocol StubRegistrationBuilder {
    var recorder: StubRecorder { get }
    var recording: RecordedCall { get }
    var sideEffects: StubBehaviorRegistry.SideEffects { get }
}

extension StubRegistrationBuilder {
    var sideEffects: StubBehaviorRegistry.SideEffects { .init() }

    func requireRuntimeMethod() -> RuntimeMethod {
        guard let method = recorder.runtimeMethod(for: recording.methodIndex) else {
            preconditionFailure("[TestDoubles] The recording closure must invoke a requirement.")
        }
        return method
    }

    func addReturnValue(_ value: Any) {
        recorder.addReturnValue(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            location: recording.registrationLocation,
            sideEffects: sideEffects,
            value: value
        )
    }

    func addThrownError<Failure: Error>(_ error: Failure) {
        addThrownError(error, for: requireRuntimeMethod())
    }

    func addThrownError<Failure: Error>(
        _ error: Failure,
        for method: RuntimeMethod
    ) {
        requireValidThrownError(error, for: method)
        addStubBehavior { _, _ -> Any in
            throw error
        }
    }

    func requireValidThrownError<Failure: Error>(
        _ error: Failure,
        for method: RuntimeMethod
    ) {
        guard method.isThrowing else {
            fatalError("[TestDoubles] thenThrow requires a throwing requirement.")
        }
        recorder.requireThrownErrorMatchesRuntimeType(error, for: method)
    }

    /// Wraps a fixed result as a queued answer, attaching the `after:` delay
    /// when one was given. A delay needs an async requirement — a synchronous
    /// caller has nowhere to suspend — so that shape fails here at
    /// registration rather than at the eventual call.
    func fixedAnswer(
        _ result: StubBehaviorRegistry.FixedResult,
        after delay: Duration?,
        using clock: (any StubClock)? = nil
    ) -> StubRecorder.QueuedAnswer {
        guard let delay else { return .value(result) }
        requireAsyncRequirement(configuring: "after:")
        precondition(
            delay >= .zero,
            "[TestDoubles] after: requires a nonnegative delay."
        )
        return .delayed(result, delay, clock ?? StubClocks.continuous)
    }

    /// Wraps a park-forever behavior as a queued answer. Suspending without
    /// ever completing needs an async requirement, so a synchronous shape
    /// fails here at registration rather than at the eventual call.
    func neverAnswer() -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "thenNeverReturn")
        return .never
    }

    /// Wraps a cancellation-reactive park as a queued answer. Waiting for the
    /// calling task's cancellation needs an async requirement, so a
    /// synchronous shape fails here at registration rather than at the
    /// eventual call.
    func awaitCancellationAnswer(
        _ outcome: StubBehaviorRegistry.FixedResult?
    ) -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "thenAwaitCancellation")
        return .awaitCancellation(outcome)
    }

    /// Creates a delayed behavior that cancels the calling task before
    /// completing with `outcome`.
    func cancelAfterAnswer(
        _ delay: Duration,
        using clock: any StubClock,
        outcome: StubBehaviorRegistry.FixedResult?
    ) -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "thenCancel")
        precondition(
            delay >= .zero,
            "[TestDoubles] thenCancel(after:) requires a nonnegative delay."
        )
        return .cancelAfter(delay, clock, outcome)
    }

    /// Wraps an explicit fall-through to the forwarding target as a queued
    /// answer. Only a `Spy` has a target to forward to, so any other double
    /// fails here at registration rather than at the eventual call.
    func forwardAnswer() -> StubRecorder.QueuedAnswer {
        guard recorder.allowsForwardingFallback else {
            fatalError(
                "[TestDoubles] thenForward requires a Spy with a forwarding "
                    + "target; this test double has none."
            )
        }
        return .forward
    }

    func unaryImmediateAnswer<Argument, Result>(
        _ handler: @escaping @Sendable (Argument) throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        let methodName = recording.name
        return .immediate { arguments in
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

    func packedImmediateAnswer<each Argument, Result>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        let methodName = recording.name
        return .immediate { arguments in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
        }
    }

    func packedSuspendingAnswer<each Argument, Result>(
        _ handler: @escaping (repeat each Argument) async throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "then")
        let methodName = recording.name
        return .suspending { arguments in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
        }
    }

    func escapingImmediateAnswer<FirstArgument, each AdditionalArgument, Result>(
        _ handler:
            @escaping @Sendable (
                FirstArgument,
                repeat each AdditionalArgument
            ) throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        let methodName = recording.name
        return .immediate { arguments in
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

    func escapingSuspendingAnswer<FirstArgument, each AdditionalArgument, Result>(
        _ handler:
            @escaping (
                FirstArgument,
                repeat each AdditionalArgument
            ) async throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "thenEscaping")
        let methodName = recording.name
        return .suspending { arguments in
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

    func countingImmediateAnswer<each Argument, Result>(
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        let counter = InvocationCounter()
        let methodName = recording.name
        return .immediate { arguments in
            try invokeCountingHandler(
                handler,
                count: counter.next(),
                with: arguments,
                method: methodName
            )
        }
    }

    func countingSuspendingAnswer<each Argument, Result>(
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) -> StubRecorder.QueuedAnswer {
        requireAsyncRequirement(configuring: "thenForEachCall")
        let counter = InvocationCounter()
        let methodName = recording.name
        return .suspending { arguments in
            try await invokeCountingHandler(
                handler,
                count: counter.next(),
                with: arguments,
                method: methodName
            )
        }
    }

    /// Validates the bare `thenAwaitCancellation()` form, whose outcome is
    /// implied by the requirement's shape: a throwing requirement rethrows
    /// the cancellation and a `Void` requirement returns. Any other shape has
    /// no implicit way to complete and must name a value.
    func requireImplicitCancellationOutcome<Result>(returning resultType: Result.Type) {
        let method = requireRuntimeMethod()
        if method.isThrowing {
            requireValidThrownError(CancellationError(), for: method)
        } else if resultType != Void.self {
            fatalError(
                "[TestDoubles] thenAwaitCancellation on a non-throwing requirement "
                    + "with a result needs a value to complete with; use "
                    + "thenAwaitCancellation(returning:)."
            )
        }
    }

    @discardableResult
    func requireAsyncRequirement(configuring feature: String) -> RuntimeMethod {
        let method = requireRuntimeMethod()
        guard method.isAsync else {
            fatalError(
                "[TestDoubles] \(feature) requires an async requirement; "
                    + "\(method.name) completes synchronously."
            )
        }
        return method
    }

    func addStubBehavior(
        _ behavior: @escaping @Sendable (_ arguments: [Any], _ methodName: String) throws -> Any
    ) {
        let methodName = recording.name
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            location: recording.registrationLocation,
            sideEffects: sideEffects
        ) { arguments in
            try behavior(arguments, methodName)
        }
    }

    func addAsyncStubBehavior(
        _ behavior: @escaping (_ arguments: [Any], _ methodName: String) async throws -> Any
    ) {
        let methodName = recording.name
        recorder.addAsyncStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            location: recording.registrationLocation,
            sideEffects: sideEffects
        ) { arguments in
            try await behavior(arguments, methodName)
        }
    }
}

extension CallPattern: StubRegistrationBuilder {}
extension StubBehaviorChain: StubRegistrationBuilder {}
extension StubInitializerBuilder: StubRegistrationBuilder {}
extension StubFailableInitializerBuilder: StubRegistrationBuilder {}
extension StubSelfResultBuilder: StubRegistrationBuilder {}
extension StubOptionalSelfResultBuilder: StubRegistrationBuilder {}

protocol StubRegistrationBuilder {
    var recorder: StubRecorder { get }
    var recording: RecordedCall { get }
}

extension StubRegistrationBuilder {
    func requireRuntimeMethod() -> MethodDescriptor {
        guard let method = recorder.runtimeMethod(for: recording.methodIndex) else {
            preconditionFailure("[TestDoubles] The recording closure must invoke a requirement.")
        }
        return method
    }

    func addReturnValue(_ value: Any) {
        recorder.addReturnValue(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            value: value
        )
    }

    func addThrownError<Failure: Error>(_ error: Failure) {
        addThrownError(error, for: requireRuntimeMethod())
    }

    func addThrownError<Failure: Error>(
        _ error: Failure,
        for method: MethodDescriptor
    ) {
        requireValidThrownError(error, for: method)
        addStubBehavior { _, _ -> Any in
            throw error
        }
    }

    func requireValidThrownError<Failure: Error>(
        _ error: Failure,
        for method: MethodDescriptor
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
        after delay: Duration?
    ) -> StubRecorder.QueuedAnswer {
        guard let delay else { return .value(result) }
        let method = requireRuntimeMethod()
        guard method.isAsync else {
            fatalError(
                "[TestDoubles] after: requires an async requirement; "
                    + "\(method.name) completes synchronously."
            )
        }
        precondition(
            delay >= .zero,
            "[TestDoubles] after: requires a nonnegative delay."
        )
        return .delayed(result, delay)
    }

    func addStubBehavior(
        _ behavior: @escaping @Sendable (_ arguments: [Any], _ methodName: String) throws -> Any
    ) {
        let methodName = recording.name
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
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
            matchers: recording.resolvedMatchers
        ) { arguments in
            try await behavior(arguments, methodName)
        }
    }
}

extension StubBuilder: StubRegistrationBuilder {}
extension StubBehaviorChain: StubRegistrationBuilder {}
extension StubInitializerBuilder: StubRegistrationBuilder {}
extension StubFailableInitializerBuilder: StubRegistrationBuilder {}
extension StubSelfResultBuilder: StubRegistrationBuilder {}
extension StubOptionalSelfResultBuilder: StubRegistrationBuilder {}

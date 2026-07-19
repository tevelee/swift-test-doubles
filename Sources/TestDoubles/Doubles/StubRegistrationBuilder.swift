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
            preconditionFailure("[TestDoubles] thenThrow requires a throwing requirement.")
        }
        recorder.requireThrownErrorMatchesRuntimeType(error, for: method)
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

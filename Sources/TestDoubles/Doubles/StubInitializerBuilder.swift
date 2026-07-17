enum InitializerDispatchOutcome: Equatable, Sendable {
    case success
    case failure
}

/// Configures a nonfailable initializer requirement.
public struct StubInitializerBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Configures the initializer to create another value backed by this stub.
    public func thenInitialize() {
        addReturnValue(InitializerDispatchOutcome.success)
    }

    /// Throws `error` whenever the recorded initializer invocation matches.
    ///
    /// The initializer must be throwing. For a concrete typed-throws
    /// initializer, `error` must be compatible with its declared error type.
    public func thenThrow<Failure: Error>(_ error: Failure) {
        addThrownError(error)
    }

    /// Handles a matching initializer invocation before creating its value.
    ///
    /// Throwing from `handler` requires a throwing initializer requirement.
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Void
    ) {
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
            return InitializerDispatchOutcome.success
        }
    }

    /// Asynchronously handles a matching initializer invocation before creating its value.
    ///
    /// The requirement must be async. Throwing from `handler` requires a throwing
    /// initializer requirement.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Void
    ) {
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
            return InitializerDispatchOutcome.success
        }
    }
}

/// Configures a failable initializer requirement.
public struct StubFailableInitializerBuilder {
    /// The result produced by a failable initializer handler.
    public enum Outcome: Sendable {
        /// Creates another value backed by this stub.
        case initialize
        /// Returns `nil` from the initializer.
        case returnNil
    }

    let recorder: StubRecorder
    let recording: RecordedCall

    /// Configures the initializer to create another value backed by this stub.
    public func thenInitialize() {
        add(.success)
    }

    /// Configures the initializer to return `nil`.
    public func thenReturnNil() {
        add(.failure)
    }

    /// Throws `error` whenever the recorded initializer invocation matches.
    ///
    /// The initializer must be throwing. For a concrete typed-throws
    /// initializer, `error` must be compatible with its declared error type.
    public func thenThrow<Failure: Error>(_ error: Failure) {
        addThrownError(error)
    }

    /// Handles a matching initializer invocation and chooses its returned outcome.
    ///
    /// Throwing from `handler` requires a throwing initializer requirement.
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Outcome
    ) {
        let methodName = recording.name
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
        ) { arguments in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
    }

    /// Asynchronously handles a matching initializer invocation and chooses its returned outcome.
    ///
    /// The requirement must be async. Throwing from `handler` requires a throwing
    /// initializer requirement.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Outcome
    ) {
        let methodName = recording.name
        recorder.addAsyncStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
        ) { arguments in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
    }

    private func add(_ outcome: InitializerDispatchOutcome) {
        addReturnValue(outcome)
    }
}

extension StubFailableInitializerBuilder.Outcome {
    fileprivate var dispatchOutcome: InitializerDispatchOutcome {
        switch self {
            case .initialize: .success
            case .returnNil: .failure
        }
    }
}

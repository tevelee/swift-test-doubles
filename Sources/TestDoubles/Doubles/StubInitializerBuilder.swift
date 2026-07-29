enum InitializerDispatchOutcome: Equatable, Sendable {
    case success
    case failure
}

/// Configures a nonfailable initializer requirement.
public struct StubInitializerBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Configures the initializer to create another value backed by this stub.
    @discardableResult
    public func thenInitialize() -> CallInteractions {
        addReturnValue(InitializerDispatchOutcome.success)
        return interactions
    }

    /// Throws `error` whenever the recorded initializer invocation matches.
    ///
    /// The initializer must be throwing. For a concrete typed-throws
    /// initializer, `error` must be compatible with its declared error type.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> CallInteractions {
        addThrownError(error)
        return interactions
    }

    /// Handles a matching initializer invocation before creating its value.
    ///
    /// Throwing from `handler` requires a throwing initializer requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Void
    ) -> CallInteractions {
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
            return InitializerDispatchOutcome.success
        }
        return interactions
    }

    /// Asynchronously handles a matching initializer invocation before creating its value.
    ///
    /// The requirement must be async. Throwing from `handler` requires a throwing
    /// initializer requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Void
    ) -> CallInteractions {
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
            return InitializerDispatchOutcome.success
        }
        return interactions
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
    @discardableResult
    public func thenInitialize() -> CallInteractions {
        add(.success)
        return interactions
    }

    /// Configures the initializer to return `nil`.
    @discardableResult
    public func thenReturnNil() -> CallInteractions {
        add(.failure)
        return interactions
    }

    /// Throws `error` whenever the recorded initializer invocation matches.
    ///
    /// The initializer must be throwing. For a concrete typed-throws
    /// initializer, `error` must be compatible with its declared error type.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> CallInteractions {
        addThrownError(error)
        return interactions
    }

    /// Handles a matching initializer invocation and chooses its returned outcome.
    ///
    /// Throwing from `handler` requires a throwing initializer requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Outcome
    ) -> CallInteractions {
        let methodName = recording.name
        recorder.addStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
        ) { arguments in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
        return interactions
    }

    /// Asynchronously handles a matching initializer invocation and chooses its returned outcome.
    ///
    /// The requirement must be async. Throwing from `handler` requires a throwing
    /// initializer requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Outcome
    ) -> CallInteractions {
        let methodName = recording.name
        recorder.addAsyncStub(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
        ) { arguments in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
        return interactions
    }

    private func add(_ outcome: InitializerDispatchOutcome) {
        addReturnValue(outcome)
    }
}

extension StubInitializerBuilder {
    fileprivate var interactions: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording)
    }
}

extension StubFailableInitializerBuilder {
    fileprivate var interactions: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording)
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

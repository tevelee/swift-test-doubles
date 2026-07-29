enum SelfResultDispatchOutcome: Sendable {
    case success
}

/// Configures an instance or static method, or getter, that returns dynamic `Self`.
public struct StubSelfResultBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns a fresh generated value whenever the recorded invocation matches.
    @discardableResult
    public func thenReturnValue() -> CallInteractions {
        addReturnValue(SelfResultDispatchOutcome.success)
        return interactions
    }

    /// Throws `error` whenever the recorded invocation matches.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> CallInteractions {
        addThrownError(error)
        return interactions
    }

    /// Handles a matching invocation before returning a fresh generated value.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. A handler that throws at runtime requires a throwing
    ///   requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Void
    ) -> CallInteractions {
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
            return SelfResultDispatchOutcome.success
        }
        return interactions
    }

    /// Asynchronously handles a matching invocation before returning a fresh generated value.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. The requirement must be async, and a handler that throws at
    ///   runtime requires a throwing requirement.
    @discardableResult
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Void
    ) -> CallInteractions {
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
            return SelfResultDispatchOutcome.success
        }
        return interactions
    }

    private var interactions: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording)
    }
}

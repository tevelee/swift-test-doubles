enum SelfResultDispatchOutcome: Sendable {
    case success
}

/// Configures an instance or static method, or getter, that returns dynamic `Self`.
public struct StubSelfResultBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns a fresh generated value whenever the recorded invocation matches.
    public func thenReturnValue() {
        addReturnValue(SelfResultDispatchOutcome.success)
    }

    /// Throws `error` whenever the recorded invocation matches.
    ///
    /// The recorded requirement must be throwing. For a concrete typed-throws
    /// requirement, `error` must be compatible with its declared error type.
    public func thenThrow<Failure: Error>(_ error: Failure) {
        addThrownError(error)
    }

    /// Handles a matching invocation before returning a fresh generated value.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. A handler that throws at runtime requires a throwing
    ///   requirement.
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Void
    ) {
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
            return SelfResultDispatchOutcome.success
        }
    }

    /// Asynchronously handles a matching invocation before returning a fresh generated value.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. The requirement must be async, and a handler that throws at
    ///   runtime requires a throwing requirement.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Void
    ) {
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
            return SelfResultDispatchOutcome.success
        }
    }
}

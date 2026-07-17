enum OptionalSelfResultDispatchOutcome: Sendable {
    case value
    case nilValue
}

/// Configures an instance or static method, or getter, that returns optional dynamic `Self`.
public struct StubOptionalSelfResultBuilder {
    /// The result produced by an optional dynamic `Self` handler.
    public enum Outcome: Sendable {
        /// Returns a fresh generated value backed by this stub's resources.
        case returnValue
        /// Returns `nil`.
        case returnNil
    }

    let recorder: StubRecorder
    let recording: RecordedCall

    /// Returns a fresh generated value whenever the recorded invocation matches.
    public func thenReturnValue() {
        addReturnValue(OptionalSelfResultDispatchOutcome.value)
    }

    /// Returns `nil` whenever the recorded invocation matches.
    public func thenReturnNil() {
        addReturnValue(OptionalSelfResultDispatchOutcome.nilValue)
    }

    /// Throws `error` whenever the recorded invocation matches.
    ///
    /// The recorded requirement must use Swift's ordinary untyped throwing
    /// convention.
    public func thenThrow<Failure: Error>(_ error: Failure) {
        addThrownError(error)
    }

    /// Handles a matching invocation and chooses whether it returns a fresh value or `nil`.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. A handler that throws at runtime requires a throwing
    ///   requirement.
    public func then<each Argument>(
        _ handler: @escaping @Sendable (repeat each Argument) throws -> Outcome
    ) {
        addStubBehavior { arguments, methodName in
            try invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
    }

    /// Asynchronously handles a matching invocation and chooses its result.
    ///
    /// - Precondition: Handler arguments match a leading prefix of the protocol
    ///   requirement's arguments in type and order. Trailing arguments may be
    ///   omitted. The requirement must be async, and a handler that throws at
    ///   runtime requires a throwing requirement.
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Outcome
    ) {
        addAsyncStubBehavior { arguments, methodName in
            try await invokeTypedHandler(handler, with: arguments, method: methodName)
                .dispatchOutcome
        }
    }
}

extension StubOptionalSelfResultBuilder.Outcome {
    fileprivate var dispatchOutcome: OptionalSelfResultDispatchOutcome {
        switch self {
            case .returnValue: .value
            case .returnNil: .nilValue
        }
    }
}

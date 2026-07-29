/// The observed completion state of one matching invocation.
///
/// Outcomes remain in invocation-entry order. A pending outcome represents a
/// call whose handler has not completed, while a forwarded outcome represents
/// a completed spy delegation whose result is owned by the ABI transport and
/// cannot be safely type-erased.
public enum InvocationOutcome<Value>: @unchecked Sendable {
    /// The call returned a value.
    case returned(Value)
    /// The call threw an error.
    case threw(any Error)
    /// The call has entered the double but has not completed.
    case pending
    /// A spy's forwarding target completed the call.
    case forwarded
    /// The runtime completed with a value unavailable as `Value`.
    case unavailable
}

extension RecordedCall {
    func typedOutcome<Value>(as type: Value.Type) -> InvocationOutcome<Value> {
        switch outcome {
            case .pending:
                return .pending
            case .returned(let value):
                guard let value = value as? Value else {
                    return .unavailable
                }
                return .returned(value)
            case .threw(let error):
                return .threw(error)
            case .forwarded:
                return .forwarded
            case .unavailable:
                return .unavailable
        }
    }
}

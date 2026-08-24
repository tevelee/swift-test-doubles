import InternalRuntimeContract

enum SynchronousAccessorRole {
    case read
    case modify

    fileprivate var queuedResultDescription: String {
        switch self {
            case .read: "read"
            case .modify: "_modify"
        }
    }

    fileprivate var dispatchDescription: String {
        switch self {
            case .read: "read"
            case .modify: "_modify"
        }
    }

    fileprivate var dispatchThrowDescription: String {
        switch self {
            case .read: "read accessor"
            case .modify: "_modify getter"
        }
    }

    fileprivate var behaviorThrowDescription: String {
        switch self {
            case .read: "read accessor"
            case .modify: "_modify accessor"
        }
    }
}

/// Evaluates endpoint-selected accessor behavior before the runtime constructs
/// coroutine storage for the yielded value.
enum SynchronousAccessorDispatch {
    struct PreparedResult {
        let value: Any
        let completionToken: RuntimeInvocationToken?
    }

    static func dispatch(
        method: MethodDescriptor,
        arguments: [Any],
        endpoint: any RuntimeInvocationEndpoint,
        role: SynchronousAccessorRole
    ) -> PreparedResult {
        switch endpoint.prepareDispatch(
            RuntimeInvocationRequest(slot: method.index, arguments: arguments)
        ) {
            case .recording:
                return PreparedResult(
                    value: endpoint.recordingAccessorResult(at: method.index),
                    completionToken: nil
                )
            case .behavior(let token, let behavior):
                return PreparedResult(
                    value: evaluate(
                        behavior,
                        method: method,
                        arguments: arguments,
                        role: role
                    ),
                    completionToken: token
                )
            case .forwarding:
                preconditionFailure(
                    "[TestDoubles] A forwarding accessor has no forwarding transport."
                )
        }
    }

    static func evaluate(
        _ behavior: RuntimeDispatchBehavior,
        method: MethodDescriptor,
        arguments: [Any],
        role: SynchronousAccessorRole
    ) -> Any {
        let result: Any
        do {
            switch behavior {
                case .fixed(let fixedResult):
                    result = try fixedResult.get()
                case .immediate(let handler):
                    result = try handler(arguments)
                case .suspending:
                    fatalError(
                        "[TestDoubles] A suspending handler was selected for synchronous \(role.dispatchDescription) dispatch of \(method.name)."
                    )
            }
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing \(role.behaviorThrowDescription) handler threw \(error)."
            )
        }

        func opened<Result>(_ type: Result.Type) -> Any {
            guard let typed = result as? Result else {
                fatalError(
                    "[TestDoubles] Stubbed return for '\(method.name)' is not \(type)."
                )
            }
            return typed
        }
        return _openExistential(method.returnType, do: opened)
    }
}

import TestDoublesRuntime

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

/// Evaluates public-layer accessor behavior before the runtime constructs
/// coroutine storage for the yielded value.
enum SynchronousAccessorDispatch {
    static func dispatch(
        method: MethodDescriptor,
        arguments: [Any],
        recorder: StubRecorder,
        role: SynchronousAccessorRole
    ) -> Any {
        func opened<Result>(_ type: Result.Type) -> Any {
            do {
                return try recorder.dispatchTyped(
                    method: method,
                    args: arguments,
                    as: type
                )
            } catch {
                fatalError(
                    "[TestDoubles] A nonthrowing \(role.dispatchThrowDescription) handler threw \(error)."
                )
            }
        }
        return _openExistential(method.returnType, do: opened)
    }

    static func evaluate(
        _ behavior: StubRecorder.StubEntry.Behavior,
        method: MethodDescriptor,
        arguments: [Any],
        role: SynchronousAccessorRole
    ) -> Any {
        let result: Any
        do {
            switch behavior {
                case .fixed(let fixedResult):
                    result = try fixedResult.get()
                case .fixedSequence:
                    preconditionFailure(
                        "[TestDoubles] A queued \(role.queuedResultDescription) result was not reserved during dispatch."
                    )
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
            requireStubbedResult(result, as: type, method: method.name)
        }
        return _openExistential(method.returnType, do: opened)
    }
}

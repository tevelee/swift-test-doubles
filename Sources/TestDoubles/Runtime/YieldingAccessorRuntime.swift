import CTestDoublesTrampoline

/// Distinguishes retained coroutine states that otherwise share one lifecycle.
enum YieldingAccessorKind: Equatable {
    case read
    case modify
}

protocol YieldingAccessorState: AnyObject, Sendable {
    var kind: YieldingAccessorKind { get }
    var yieldedStorage: UnsafeMutableRawPointer? { get }
    func finish(isAborting: Bool)
}

/// Centralizes the retain/consume boundary shared by `_read` and `_modify`.
enum YieldingAccessorRuntime {
    static func retain(
        _ state: any YieldingAccessorState
    ) -> UnsafeMutableRawPointer {
        RetainedRuntimeState.retain(state as AnyObject)
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        as expectedKind: YieldingAccessorKind,
        isAborting: Bool,
        invalidTypeMessage: @autoclosure () -> String
    ) {
        let object = RetainedRuntimeState.consume(
            AnyObject.self,
            from: rawState,
            invalidTypeMessage: invalidTypeMessage()
        )
        guard let state = object as? any YieldingAccessorState,
            state.kind == expectedKind
        else {
            preconditionFailure(invalidTypeMessage())
        }
        state.finish(isAborting: isAborting)
    }

    /// Derives the arm64e resume discriminator shared by `yield_once_2`
    /// read and modify witnesses.
    static func resumeDiscriminator(for method: MethodDescriptor) -> UInt16? {
        let yieldSpelling: String
        switch method.result.layout {
            case .indirect:
                yieldSpelling = "indirect"
            case .void, .integer, .floatingPoint, .aggregate:
                guard let spelling = pointerAuthTypeSpelling(method.returnType) else {
                    return nil
                }
                yieldSpelling = spelling
        }
        let spelling = "yield_once_2:1:\(yieldSpelling):"
        let bytes = Array(spelling.utf8)
        return bytes.withUnsafeBufferPointer {
            td_function_discriminator($0.baseAddress, $0.count)
        }
    }
}

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

/// Evaluates synchronous accessor handlers and validates their dynamic result
/// before either coroutine constructs yielded storage.
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

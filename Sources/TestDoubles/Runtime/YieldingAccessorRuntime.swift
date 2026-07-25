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

    /// Derives the arm64e resume discriminator for a `yield_once_2` `read`
    /// witness. `read` can yield either directly (small, non-generic
    /// results) or indirectly (everything else), so the shape is derived
    /// from the getter's own value-size ABI classification.
    static func readResumeDiscriminator(for method: MethodDescriptor) -> UInt16? {
        let isIndirect: Bool
        switch method.result.layout {
            case .indirect:
                isIndirect = true
            case .void, .integer, .floatingPoint, .aggregate:
                isIndirect = false
        }
        return resumeDiscriminator(isIndirect: isIndirect, returnType: method.returnType)
    }

    /// Derives the arm64e resume discriminator for a `yield_once_2` `modify`
    /// witness. Unlike `read`, `modify` always yields an address for
    /// in-place mutation, regardless of the property's value size -- so the
    /// yield is unconditionally indirect, and `method.result.layout`'s
    /// value-size classification (which only describes how the *getter*
    /// returns the value) does not apply here.
    static func modifyResumeDiscriminator(for method: MethodDescriptor) -> UInt16? {
        resumeDiscriminator(isIndirect: true, returnType: method.returnType)
    }

    /// The pure core shared by `readResumeDiscriminator(for:)` and
    /// `modifyResumeDiscriminator(for:)`, factored out so it is directly
    /// testable against a live Swift compiler without constructing a full
    /// `MethodDescriptor`: only the caller-visible yield shape (whether
    /// Swift formally returns the value indirectly) and the yielded type feed
    /// the spelling, mirroring IRGen's own `PointerAuthEntity` string scheme
    /// for a `yield_once_2` coroutine continuation.
    ///
    /// `SILFunctionType::getCoroutineYieldTypesDiscriminator`
    /// (lib/SIL/IR/SILFunctionType.cpp) spells an indirectly-yielded value as
    /// `"inout"` (`yield.isIndirectInOut()`), not `"indirect"`
    /// (`yield.isFormalIndirect()`, used only for ordinary indirect
    /// parameters/results elsewhere in that file) -- every `yield_once_2`
    /// read/modify accessor yields an address, which is the "inout" shape
    /// regardless of whether the property itself is mutable. Confirmed
    /// against a live Swift 6.3 compiler: `"yield_once_2:1:inout:"` hashes to
    /// the exact discriminator (33953) the compiler emits both for a
    /// formally indirect `read` and for every `modify` witness.
    static func resumeDiscriminator(
        isIndirect: Bool,
        returnType: Any.Type
    ) -> UInt16? {
        let yieldSpelling: String
        if isIndirect {
            yieldSpelling = "inout"
        } else {
            guard let spelling = pointerAuthTypeSpelling(returnType) else {
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
import TestDoublesRuntime

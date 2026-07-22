import CTestDoublesTrampoline
import Echo

protocol ReadCoroutineForwardingState: AnyObject, Sendable {
    var yieldedStorage: UnsafeMutableRawPointer? { get }
    func finish()
}

@_cdecl("td_swift_read_trampoline_handler")
func td_swift_read_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) -> TDReadCoroutineResult {
    guard let rawFrame else {
        fatalError("[TestDoubles] read trampoline received a null call frame.")
    }
    return ReadCoroutineRuntime.prepare(rawFrame)
}

@_cdecl("td_swift_read_trampoline_resume_handler")
func td_swift_read_trampoline_resume_handler(
    _ rawState: UnsafeMutableRawPointer?,
    _ isAborting: Bool
) {
    guard let rawState else {
        fatalError("[TestDoubles] read coroutine resumed without retained state.")
    }
    ReadCoroutineRuntime.finish(rawState, isAborting: isAborting)
}

enum ReadCoroutineRuntime {
    /// Keeps a configured borrowed result alive until Swift resumes the
    /// yield_once_2 coroutine. Formally indirect results additionally own an
    /// initialized value buffer whose address is yielded to the caller.
    private final class ConfiguredState {
        let buffer: ManagedValueBuffer

        var storage: UnsafeMutableRawPointer { buffer.storage }

        init(result: Any, method: MethodDescriptor) {
            buffer = ManagedValueBuffer(
                type: method.returnType,
                minimumByteCount: 32
            )
            buffer.zeroBorrowedBytes()
            RuntimeResultEncoder.initializeDirectValue(
                result,
                expectedType: method.returnType,
                to: buffer.storage
            )
            buffer.markInitialized()
        }
    }

    /// Retains either owned configured storage or the target Spy coroutine
    /// until Swift resumes the fabricated outer coroutine exactly once.
    private final class DispatchState {
        private enum Storage {
            case configured(ConfiguredState)
            case forwarded(any ReadCoroutineForwardingState)
        }

        let yieldedStorage: UnsafeMutableRawPointer?
        private let storage: Storage

        init(
            configured: ConfiguredState,
            resultIsIndirect: Bool
        ) {
            storage = .configured(configured)
            yieldedStorage = resultIsIndirect ? configured.storage : nil
        }

        init(forwarded: any ReadCoroutineForwardingState) {
            storage = .forwarded(forwarded)
            yieldedStorage = forwarded.yieldedStorage
        }

        func finish() {
            guard case .forwarded(let forwarded) = storage else { return }
            forwarded.finish()
        }
    }

    static func prepare(
        _ rawFrame: UnsafeMutablePointer<TDCallFrame>
    ) -> TDReadCoroutineResult {
        let frame = TrampolineCallFrame(rawFrame)
        let dispatchIndex = frame.slot
        guard let invocation = ResolvedFabricatedInvocation.resolve(in: frame) else {
            fatalError(
                "[TestDoubles] read trampoline could not resolve recorder dispatch \(dispatchIndex)."
            )
        }
        let recorder = invocation.recorder
        let method = invocation.requireMethod(
            failureMessage:
                "[TestDoubles] read trampoline could not resolve recorder dispatch \(dispatchIndex)."
        )
        guard method.kind == .getter else {
            fatalError(
                "[TestDoubles] read trampoline could not resolve recorder dispatch \(dispatchIndex)."
            )
        }

        #if arch(x86_64)
            let argumentOffset = 2
        #else
            let argumentOffset = 1
        #endif
        let arguments = RuntimeArgumentDecoder.decode(
            for: method,
            from: frame,
            initialGeneralPurposeOffset: argumentOffset
        ).values
        let state: DispatchState
        if let forwarder = invocation.forwarder {
            switch recorder.prepareDispatch(method: method, args: arguments) {
                case .forwarding:
                    state = DispatchState(
                        forwarded: forwarder.makeReadState(
                            for: method,
                            frame: frame
                        )
                    )

                case .placeholder:
                    state = makeConfiguredState(
                        result: placeholderResult(for: method),
                        method: method,
                        frame: frame
                    )

                case .behavior(let behavior):
                    state = makeConfiguredState(
                        result: behaviorResult(
                            behavior,
                            method: method,
                            arguments: arguments
                        ),
                        method: method,
                        frame: frame
                    )
            }
        } else {
            state = makeConfiguredState(
                result: dispatch(
                    method: method,
                    arguments: arguments,
                    recorder: recorder
                ),
                method: method,
                frame: frame
            )
        }

        return TDReadCoroutineResult(
            state: RetainedRuntimeState.retain(state),
            yieldedStorage: state.yieldedStorage
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        // Swift 6.3 lowers both normal completion and unwind of yield_once_2
        // through the same continuation. The outer abort bit is therefore not
        // forwarded as a distinct target argument.
        _ = isAborting
        let state = RetainedRuntimeState.consume(
            DispatchState.self,
            from: rawState,
            invalidTypeMessage:
                "[TestDoubles] read coroutine state has an invalid type."
        )
        state.finish()
    }

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

    private static func dispatch(
        method: MethodDescriptor,
        arguments: [Any],
        recorder: StubRecorder
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
                    "[TestDoubles] A nonthrowing read accessor handler threw \(error)."
                )
            }
        }
        return _openExistential(method.returnType, do: opened)
    }

    private static func makeConfiguredState(
        result: Any,
        method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> DispatchState {
        let configured = ConfiguredState(result: result, method: method)
        let resultIsIndirect: Bool
        if case .indirect = method.result.layout {
            resultIsIndirect = true
        } else {
            resultIsIndirect = false
            RuntimeResultEncoder.encodeBorrowedDirectValue(
                from: configured.storage,
                layout: method.result.layout,
                into: frame
            )
        }
        return DispatchState(
            configured: configured,
            resultIsIndirect: resultIsIndirect
        )
    }

    private static func placeholderResult(
        for method: MethodDescriptor
    ) -> Any {
        func opened<Result>(_ type: Result.Type) -> Any {
            RecordingReturnPlaceholderContext.requiredValue(
                for: type,
                method: method.name
            )
        }
        return _openExistential(method.returnType, do: opened)
    }

    private static func behaviorResult(
        _ behavior: StubRecorder.StubEntry.Behavior,
        method: MethodDescriptor,
        arguments: [Any]
    ) -> Any {
        let result: Any
        do {
            switch behavior {
                case .fixed(let fixedResult):
                    result = try fixedResult.get()
                case .fixedSequence:
                    preconditionFailure(
                        "[TestDoubles] A queued read result was not reserved during dispatch."
                    )
                case .immediate(let handler):
                    result = try handler(arguments)
                case .suspending:
                    fatalError(
                        "[TestDoubles] A suspending handler was selected for synchronous read dispatch of \(method.name)."
                    )
            }
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing read accessor handler threw \(error)."
            )
        }

        func opened<Result>(_ type: Result.Type) -> Any {
            requireStubbedResult(result, as: type, method: method.name)
        }
        return _openExistential(method.returnType, do: opened)
    }
}

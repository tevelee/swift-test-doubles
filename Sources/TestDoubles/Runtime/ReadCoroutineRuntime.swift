import CTestDoublesTrampoline
import Echo

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
    private final class ConfiguredState: YieldingAccessorState, @unchecked Sendable {
        let kind = YieldingAccessorKind.read
        let yieldedStorage: UnsafeMutableRawPointer?
        let buffer: ManagedValueBuffer

        init(
            result: Any,
            method: MethodDescriptor,
            frame: TrampolineCallFrame
        ) {
            buffer = ManagedValueBuffer(
                type: method.returnType,
                minimumByteCount: 32
            )
            buffer.zeroBorrowedBytes()
            RuntimeValueTransport.initializeDirectValue(
                result,
                expectedType: method.returnType,
                to: buffer.storage
            )
            buffer.markInitialized()
            if case .indirect = method.result.layout {
                yieldedStorage = buffer.storage
            } else {
                yieldedStorage = nil
                RuntimeValueTransport.encodeBorrowedDirectValue(
                    from: buffer.storage,
                    layout: method.result.layout,
                    into: frame
                )
            }
        }

        func finish(isAborting: Bool) { _ = isAborting }
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
        let state: any YieldingAccessorState
        if let forwarder = invocation.forwarder {
            switch recorder.prepareDispatch(method: method, args: arguments) {
                case .forwarding:
                    state = forwarder.makeReadState(
                        for: method,
                        frame: frame
                    )

                case .placeholder:
                    state = ConfiguredState(
                        result: placeholderResult(for: method),
                        method: method,
                        frame: frame
                    )

                case .behavior(let behavior):
                    state = ConfiguredState(
                        result: SynchronousAccessorDispatch.evaluate(
                            behavior,
                            method: method,
                            arguments: arguments,
                            role: .read
                        ),
                        method: method,
                        frame: frame
                    )
            }
        } else {
            state = ConfiguredState(
                result: SynchronousAccessorDispatch.dispatch(
                    method: method,
                    arguments: arguments,
                    recorder: recorder,
                    role: .read
                ),
                method: method,
                frame: frame
            )
        }

        return TDReadCoroutineResult(
            state: YieldingAccessorRuntime.retain(state),
            yieldedStorage: state.yieldedStorage
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        YieldingAccessorRuntime.finish(
            rawState,
            as: .read,
            isAborting: isAborting,
            invalidTypeMessage:
                "[TestDoubles] read coroutine state has an invalid type."
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

}

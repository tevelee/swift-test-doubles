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
    /// Keeps the borrowed result alive until Swift resumes or aborts the
    /// yield_once_2 coroutine. Formally indirect results additionally own an
    /// initialized value buffer whose address is yielded to the caller.
    private final class DispatchState {
        let storage: UnsafeMutableRawPointer
        let metadata: Metadata

        init(result: Any, method: MethodDescriptor) {
            let metadata = reflect(method.returnType)
            let storage = metadata.allocateValueBuffer(minimumByteCount: 32)
            storage.initializeMemory(
                as: UInt8.self,
                repeating: 0,
                count: metadata.valueBufferByteCount(minimum: 32)
            )
            RuntimeResultEncoder.initializeDirectValue(
                result,
                expectedType: method.returnType,
                to: storage
            )
            self.storage = storage
            self.metadata = metadata
        }

        deinit {
            metadata.vwt.destroy(storage)
            storage.deallocate()
        }
    }

    static func prepare(
        _ rawFrame: UnsafeMutablePointer<TDCallFrame>
    ) -> TDReadCoroutineResult {
        let frame = TrampolineCallFrame(rawFrame)
        let dispatchIndex = frame.slot
        guard let recorder = RuntimeTrampolineHandler.findRecorder(in: frame),
            let method = recorder.runtimeMethod(for: dispatchIndex),
            method.kind == .getter
        else {
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
        let result = dispatch(method: method, arguments: arguments, recorder: recorder)
        let state = DispatchState(result: result, method: method)

        if case .indirect = method.result.layout {
            return TDReadCoroutineResult(
                state: Unmanaged.passRetained(state).toOpaque(),
                yieldedStorage: state.storage
            )
        }
        RuntimeResultEncoder.encodeBorrowedDirectValue(
            from: state.storage,
            layout: method.result.layout,
            into: frame
        )
        return TDReadCoroutineResult(
            state: Unmanaged.passRetained(state).toOpaque(),
            yieldedStorage: nil
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        _ = isAborting
        _ = Unmanaged<DispatchState>.fromOpaque(rawState).takeRetainedValue()
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
}

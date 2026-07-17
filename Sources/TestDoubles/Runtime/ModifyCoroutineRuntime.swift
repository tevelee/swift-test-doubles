import CTestDoublesTrampoline
import Echo

@_cdecl("td_swift_modify_trampoline_handler")
func td_swift_modify_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) -> TDModifyCoroutineResult {
    guard let rawFrame else {
        fatalError("[TestDoubles] _modify trampoline received a null call frame.")
    }
    return ModifyCoroutineRuntime.prepare(rawFrame)
}

@_cdecl("td_swift_modify_trampoline_resume_handler")
func td_swift_modify_trampoline_resume_handler(
    _ rawState: UnsafeMutableRawPointer?,
    _ isAborting: Bool
) {
    guard let rawState else {
        fatalError("[TestDoubles] _modify trampoline resumed without retained state.")
    }
    ModifyCoroutineRuntime.finish(rawState, isAborting: isAborting)
}

private enum ModifyCoroutineRuntime {
    /// Owns the initialized value yielded by one `_modify` invocation until
    /// Swift resumes the coroutine. The resume hook consumes the retain and
    /// writes the final value through the paired setter on both normal and
    /// abort/unwind paths.
    private final class DispatchState {
        let getter: MethodDescriptor
        let setter: MethodDescriptor
        let recorder: StubRecorder
        let indices: [Any]
        let storage: UnsafeMutableRawPointer
        let metadata: Metadata

        init(
            getter: MethodDescriptor,
            setter: MethodDescriptor,
            recorder: StubRecorder,
            indices: [Any],
            storage: UnsafeMutableRawPointer,
            metadata: Metadata
        ) {
            self.getter = getter
            self.setter = setter
            self.recorder = recorder
            self.indices = indices
            self.storage = storage
            self.metadata = metadata
        }
    }

    static func prepare(
        _ rawFrame: UnsafeMutablePointer<TDCallFrame>
    ) -> TDModifyCoroutineResult {
        let frame = TrampolineCallFrame(rawFrame)
        let getterIndex = frame.slot
        guard let recorder = RuntimeTrampolineHandler.findRecorder(in: frame) else {
            fatalError(
                "[TestDoubles] _modify trampoline could not resolve recorder for getter slot \(getterIndex)."
            )
        }
        switch recorder.mode {
            case .normal:
                break
            case .capturing:
                fatalError(
                    "[TestDoubles] Compound assignment and inout mutation cannot be captured while configuring or verifying a Stub. Capture the ordinary getter or direct setter instead."
                )
        }
        guard
            let (getter, setter) = recorder.modifyDispatchMethods(
                forGetterIndex: getterIndex
            )
        else {
            fatalError(
                "[TestDoubles] _modify getter slot \(getterIndex) is not followed by a compatible setter."
            )
        }

        let indices = RuntimeArgumentDecoder.decode(
            for: getter,
            from: frame,
            initialGeneralPurposeOffset: 1
        ).values
        let result: Any
        do {
            result = try recorder.dispatch(method: getter, args: indices)
        } catch {
            fatalError("[TestDoubles] A nonthrowing _modify getter handler threw \(error).")
        }

        let metadata = reflect(getter.returnType)
        let storage = metadata.allocateValueBuffer()
        RuntimeResultEncoder.initializeDirectValue(
            result,
            expectedType: getter.returnType,
            to: storage
        )
        let state = DispatchState(
            getter: getter,
            setter: setter,
            recorder: recorder,
            indices: indices,
            storage: storage,
            metadata: metadata
        )
        return TDModifyCoroutineResult(
            state: Unmanaged.passRetained(state).toOpaque(),
            yieldedStorage: storage
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        let state = Unmanaged<DispatchState>.fromOpaque(rawState).takeRetainedValue()
        let value: Any
        if reflect(state.getter.returnType) is FunctionMetadata {
            value = FunctionReabstraction.boxDirectArgument(
                type: state.getter.returnType,
                source: state.storage
            )
        } else {
            value = boxValue(
                type: state.getter.returnType,
                source: state.storage
            )
        }
        state.metadata.vwt.destroy(state.storage)
        state.storage.deallocate()

        // Swift's yield-once unwind is non-transactional: writes made before a
        // thrown error remain visible, so the abort path requires writeback too.
        _ = isAborting
        do {
            _ = try state.recorder.dispatch(
                method: state.setter,
                args: [value] + state.indices
            )
        } catch {
            fatalError("[TestDoubles] A nonthrowing _modify setter handler threw \(error).")
        }
    }
}

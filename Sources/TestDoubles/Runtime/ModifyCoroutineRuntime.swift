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
    /// Owns the configured value yielded by one `_modify` invocation until
    /// Swift resumes the coroutine, then writes the final value through the
    /// paired setter on both normal and abort/unwind paths.
    private final class ConfiguredState: YieldingAccessorState, @unchecked Sendable {
        let kind = YieldingAccessorKind.modify
        let getter: MethodDescriptor
        let setter: MethodDescriptor
        let recorder: StubRecorder
        let indices: [Any]
        let buffer: ManagedValueBuffer
        let skipsForwardingSetter: Bool

        var yieldedStorage: UnsafeMutableRawPointer? { buffer.storage }
        private var storage: UnsafeMutableRawPointer { buffer.storage }

        init(
            getter: MethodDescriptor,
            setter: MethodDescriptor,
            recorder: StubRecorder,
            indices: [Any],
            buffer: ManagedValueBuffer,
            skipsForwardingSetter: Bool
        ) {
            self.getter = getter
            self.setter = setter
            self.recorder = recorder
            self.indices = indices
            self.buffer = buffer
            self.skipsForwardingSetter = skipsForwardingSetter
        }

        func finish(isAborting: Bool) {
            let value: Any
            if reflect(getter.returnType) is FunctionMetadata {
                value = FunctionReabstraction.boxDirectArgument(
                    type: getter.returnType,
                    source: storage
                )
            } else {
                value = boxValue(
                    type: getter.returnType,
                    source: storage
                )
            }
            buffer.destroyInitializedValue()

            // Swift's yield-once unwind is non-transactional: writes made
            // before a thrown error remain visible, so abort requires the
            // same configured writeback as normal completion.
            _ = isAborting
            dispatchSetter(value)
        }

        private func dispatchSetter(_ value: Any) {
            let arguments = [value] + indices
            if skipsForwardingSetter {
                switch recorder.prepareDispatch(
                    method: setter,
                    args: arguments
                ) {
                    case .placeholder, .forwarding:
                        // A getter override owns this outer coroutine. A
                        // falling-through setter must not enter the real
                        // target after the target `_modify` was skipped.
                        return
                    case .behavior(let behavior):
                        _ = SynchronousAccessorDispatch.evaluate(
                            behavior,
                            method: setter,
                            arguments: arguments,
                            role: .modify
                        )
                        return
                }
            }

            do {
                _ = try recorder.dispatch(
                    method: setter,
                    args: arguments
                )
            } catch {
                fatalError(
                    "[TestDoubles] A nonthrowing _modify setter handler threw \(error)."
                )
            }
        }
    }

    static func prepare(
        _ rawFrame: UnsafeMutablePointer<TDCallFrame>
    ) -> TDModifyCoroutineResult {
        let frame = TrampolineCallFrame(rawFrame)
        let getterIndex = frame.slot
        guard let invocation = ResolvedFabricatedInvocation.resolve(in: frame) else {
            fatalError(
                "[TestDoubles] _modify trampoline could not resolve recorder for getter slot \(getterIndex)."
            )
        }
        let recorder = invocation.recorder
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
        let state: any YieldingAccessorState
        if let forwarder = invocation.forwarder {
            switch recorder.prepareDispatch(method: getter, args: indices) {
                case .forwarding:
                    state = forwarder.makeModifyState(
                        for: getter,
                        frame: frame
                    )

                case .placeholder:
                    preconditionFailure(
                        "[TestDoubles] _modify capture must fail before dispatch."
                    )

                case .behavior(let behavior):
                    state = makeConfiguredState(
                        result: SynchronousAccessorDispatch.evaluate(
                            behavior,
                            method: getter,
                            arguments: indices,
                            role: .modify
                        ),
                        getter: getter,
                        setter: setter,
                        recorder: recorder,
                        indices: indices,
                        skipsForwardingSetter: true
                    )
            }
        } else {
            state = makeConfiguredState(
                result: SynchronousAccessorDispatch.dispatch(
                    method: getter,
                    arguments: indices,
                    recorder: recorder,
                    role: .modify
                ),
                getter: getter,
                setter: setter,
                recorder: recorder,
                indices: indices,
                skipsForwardingSetter: false
            )
        }
        guard let yieldedStorage = state.yieldedStorage else {
            preconditionFailure(
                "[TestDoubles] _modify coroutine produced null yielded storage."
            )
        }
        return TDModifyCoroutineResult(
            state: YieldingAccessorRuntime.retain(state),
            yieldedStorage: yieldedStorage
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        YieldingAccessorRuntime.finish(
            rawState,
            as: .modify,
            isAborting: isAborting,
            invalidTypeMessage:
                "[TestDoubles] _modify coroutine state has an invalid type."
        )
    }

    private static func makeConfiguredState(
        result: Any,
        getter: MethodDescriptor,
        setter: MethodDescriptor,
        recorder: StubRecorder,
        indices: [Any],
        skipsForwardingSetter: Bool
    ) -> any YieldingAccessorState {
        let buffer = ManagedValueBuffer(type: getter.returnType)
        RuntimeValueTransport.initializeDirectValue(
            result,
            expectedType: getter.returnType,
            to: buffer.storage
        )
        buffer.markInitialized()
        return ConfiguredState(
            getter: getter,
            setter: setter,
            recorder: recorder,
            indices: indices,
            buffer: buffer,
            skipsForwardingSetter: skipsForwardingSetter
        )
    }
}

import CTestDoublesTrampoline
import EchoRuntimeReflection
import EchoRuntimeSupport
import InternalRuntimeContract
import TestDoublesRuntimeMetadata

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
        let endpoint: any RuntimeInvocationEndpoint
        let indices: [Any]
        let buffer: ValueStorage
        let skipsForwardingSetter: Bool
        let getterCompletionToken: RuntimeInvocationToken?

        var yieldedStorage: UnsafeMutableRawPointer? { buffer.storage }
        private var storage: UnsafeMutableRawPointer { buffer.storage }

        init(
            getter: MethodDescriptor,
            setter: MethodDescriptor,
            endpoint: any RuntimeInvocationEndpoint,
            indices: [Any],
            buffer: ValueStorage,
            skipsForwardingSetter: Bool,
            getterCompletionToken: RuntimeInvocationToken?
        ) {
            self.getter = getter
            self.setter = setter
            self.endpoint = endpoint
            self.indices = indices
            self.buffer = buffer
            self.skipsForwardingSetter = skipsForwardingSetter
            self.getterCompletionToken = getterCompletionToken
        }

        func finish(isAborting: Bool) {
            let value: Any
            if FunctionTypeInfo(reflecting: getter.returnType) != nil {
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
            if let getterCompletionToken {
                endpoint.completeInvocation(
                    getterCompletionToken,
                    outcome: .unavailable
                )
            }
        }

        private func dispatchSetter(_ value: Any) {
            let arguments = [value] + indices
            if skipsForwardingSetter {
                switch endpoint.prepareDispatch(
                    RuntimeInvocationRequest(
                        slot: setter.index,
                        arguments: arguments
                    )
                ) {
                    case .recording:
                        // A getter override owns this outer coroutine. A
                        // falling-through setter must not enter the real
                        // target after the target `_modify` was skipped.
                        return
                    case .forwarding(let token):
                        endpoint.completeForwardedInvocation(token)
                        return
                    case .behavior(let token, let behavior):
                        let result = SynchronousAccessorDispatch.evaluate(
                            behavior,
                            method: setter,
                            arguments: arguments,
                            role: .modify
                        )
                        endpoint.completeInvocation(
                            token,
                            outcome: .returned(result)
                        )
                        return
                }
            }

            switch endpoint.prepareDispatch(
                RuntimeInvocationRequest(slot: setter.index, arguments: arguments)
            ) {
                case .recording:
                    _ = endpoint.recordingAccessorResult(at: setter.index)
                case .behavior(let token, let behavior):
                    let result = SynchronousAccessorDispatch.evaluate(
                        behavior,
                        method: setter,
                        arguments: arguments,
                        role: .modify
                    )
                    endpoint.completeInvocation(
                        token,
                        outcome: .returned(result)
                    )
                case .forwarding:
                    preconditionFailure(
                        "[TestDoubles] A forwarding setter entered configured _modify writeback."
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
        let runtimeGetter = invocation.requireRuntimeMethod(
            failureMessage:
                "[TestDoubles] _modify trampoline could not resolve runtime dispatch \(getterIndex)."
        )
        switch invocation.endpoint.invocationMode {
            case .normal:
                break
            case .capturing:
                fatalError(
                    "[TestDoubles] Compound assignment and inout mutation cannot be captured while configuring or verifying a Stub. Capture the ordinary getter or direct setter instead."
                )
        }
        guard
            let dispatch = invocation.endpoint.modifyDispatch(
                forGetterSlot: getterIndex
            ),
            dispatch.getterSlot == getterIndex,
            let runtimeSetter = invocation.invocation.method(at: dispatch.setterSlot)
        else {
            fatalError(
                "[TestDoubles] _modify getter slot \(getterIndex) is not followed by a compatible setter."
            )
        }
        let getter = runtimeGetter.descriptor
        let setter = runtimeSetter.descriptor

        let indices = RuntimeArgumentDecoder.decode(
            runtimeGetter.coroutineDecodingPlan(
                initialGeneralPurposeOffset: 1,
                consumeOwnedArguments: invocation.forwarder == nil
            ),
            from: frame,
        ).values
        let state: any YieldingAccessorState
        if let forwarder = invocation.forwarder {
            switch invocation.endpoint.prepareDispatch(
                RuntimeInvocationRequest(slot: getter.index, arguments: indices)
            ) {
                case .forwarding(let token):
                    state = ForwardingCompletionYieldingState(
                        base: forwarder.makeModifyState(
                            for: runtimeGetter,
                            frame: frame
                        ),
                        endpoint: invocation.endpoint,
                        token: token
                    )

                case .recording:
                    preconditionFailure(
                        "[TestDoubles] _modify capture must fail before dispatch."
                    )

                case .behavior(let token, let behavior):
                    state = makeConfiguredState(
                        result: SynchronousAccessorDispatch.evaluate(
                            behavior,
                            method: getter,
                            arguments: indices,
                            role: .modify
                        ),
                        getter: getter,
                        setter: setter,
                        endpoint: invocation.endpoint,
                        indices: indices,
                        skipsForwardingSetter: true,
                        completionToken: token
                    )
            }
        } else {
            let prepared = SynchronousAccessorDispatch.dispatch(
                method: getter,
                arguments: indices,
                endpoint: invocation.endpoint,
                role: .modify
            )
            state = makeConfiguredState(
                result: prepared.value,
                getter: getter,
                setter: setter,
                endpoint: invocation.endpoint,
                indices: indices,
                skipsForwardingSetter: false,
                completionToken: prepared.completionToken
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
        endpoint: any RuntimeInvocationEndpoint,
        indices: [Any],
        skipsForwardingSetter: Bool,
        completionToken: RuntimeInvocationToken?
    ) -> any YieldingAccessorState {
        let buffer = ValueStorage(type: getter.returnType)
        RuntimeValueTransport.initializeDirectValue(
            result,
            expectedType: getter.returnType,
            to: buffer.storage
        )
        buffer.markInitialized()
        return ConfiguredState(
            getter: getter,
            setter: setter,
            endpoint: endpoint,
            indices: indices,
            buffer: buffer,
            skipsForwardingSetter: skipsForwardingSetter,
            getterCompletionToken: completionToken
        )
    }
}

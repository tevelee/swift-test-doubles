import CTestDoublesTrampoline
import Echo

protocol ModifyCoroutineForwardingState: AnyObject, Sendable {
    var yieldedStorage: UnsafeMutableRawPointer { get }
    func finish(isAborting: Bool)
}

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
    private final class ConfiguredState {
        let getter: MethodDescriptor
        let setter: MethodDescriptor
        let recorder: StubRecorder
        let indices: [Any]
        let buffer: ManagedValueBuffer
        let skipsForwardingSetter: Bool

        var storage: UnsafeMutableRawPointer { buffer.storage }

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
                        _ = ModifyCoroutineRuntime.behaviorResult(
                            behavior,
                            method: setter,
                            arguments: arguments
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

    /// Retains either configured storage or the real target coroutine until
    /// Swift resumes the fabricated outer coroutine exactly once.
    private final class DispatchState {
        private enum Storage {
            case configured(ConfiguredState)
            case forwarded(any ModifyCoroutineForwardingState)
        }

        let yieldedStorage: UnsafeMutableRawPointer
        private let storage: Storage

        init(configured: ConfiguredState) {
            storage = .configured(configured)
            yieldedStorage = configured.storage
        }

        init(forwarded: any ModifyCoroutineForwardingState) {
            storage = .forwarded(forwarded)
            yieldedStorage = forwarded.yieldedStorage
        }

        func finish(isAborting: Bool) {
            switch storage {
                case .configured(let configured):
                    configured.finish(isAborting: isAborting)
                case .forwarded(let forwarded):
                    forwarded.finish(isAborting: isAborting)
            }
        }
    }

    static func prepare(
        _ rawFrame: UnsafeMutablePointer<TDCallFrame>
    ) -> TDModifyCoroutineResult {
        let frame = TrampolineCallFrame(rawFrame)
        let getterIndex = frame.slot
        guard let key = UnsafeRawPointer(bitPattern: frame.context),
            let target = FabricatedInvocationRegistry.resolveOptional(key)
        else {
            fatalError(
                "[TestDoubles] _modify trampoline could not resolve recorder for getter slot \(getterIndex)."
            )
        }
        let recorder = target.recorderOrReject(slot: getterIndex)
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
        let state: DispatchState
        if let forwarder = target.forwarder {
            switch recorder.prepareDispatch(method: getter, args: indices) {
                case .forwarding:
                    state = DispatchState(
                        forwarded: forwarder.makeModifyState(
                            for: getter,
                            frame: frame
                        )
                    )

                case .placeholder:
                    preconditionFailure(
                        "[TestDoubles] _modify capture must fail before dispatch."
                    )

                case .behavior(let behavior):
                    state = makeConfiguredState(
                        result: behaviorResult(
                            behavior,
                            method: getter,
                            arguments: indices
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
                result: dispatch(
                    method: getter,
                    arguments: indices,
                    recorder: recorder
                ),
                getter: getter,
                setter: setter,
                recorder: recorder,
                indices: indices,
                skipsForwardingSetter: false
            )
        }
        return TDModifyCoroutineResult(
            state: Unmanaged.passRetained(state).toOpaque(),
            yieldedStorage: state.yieldedStorage
        )
    }

    static func finish(
        _ rawState: UnsafeMutableRawPointer,
        isAborting: Bool
    ) {
        let state = Unmanaged<DispatchState>.fromOpaque(rawState).takeRetainedValue()
        state.finish(isAborting: isAborting)
    }

    private static func makeConfiguredState(
        result: Any,
        getter: MethodDescriptor,
        setter: MethodDescriptor,
        recorder: StubRecorder,
        indices: [Any],
        skipsForwardingSetter: Bool
    ) -> DispatchState {
        let buffer = ManagedValueBuffer(type: getter.returnType)
        RuntimeResultEncoder.initializeDirectValue(
            result,
            expectedType: getter.returnType,
            to: buffer.storage
        )
        buffer.markInitialized()
        return DispatchState(
            configured: ConfiguredState(
                getter: getter,
                setter: setter,
                recorder: recorder,
                indices: indices,
                buffer: buffer,
                skipsForwardingSetter: skipsForwardingSetter
            )
        )
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
                    "[TestDoubles] A nonthrowing _modify getter handler threw \(error)."
                )
            }
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
                        "[TestDoubles] A queued _modify result was not reserved during dispatch."
                    )
                case .immediate(let handler):
                    result = try handler(arguments)
                case .suspending:
                    fatalError(
                        "[TestDoubles] A suspending handler was selected for synchronous _modify dispatch of \(method.name)."
                    )
            }
        } catch {
            fatalError(
                "[TestDoubles] A nonthrowing _modify accessor handler threw \(error)."
            )
        }

        func opened<Result>(_ type: Result.Type) -> Any {
            requireStubbedResult(result, as: type, method: method.name)
        }
        return _openExistential(method.returnType, do: opened)
    }
}

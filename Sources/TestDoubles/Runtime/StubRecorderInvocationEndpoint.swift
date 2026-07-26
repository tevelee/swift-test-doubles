import InternalRuntimeContract
import TestDoublesRuntime

/// Immutable requirement catalog shared by a fabricated stub's semantic
/// recorder and invocation endpoint.
///
/// This remains in the semantic target: it maps trampoline slots to
/// test-double requirements, without exposing runtime storage or ABI metadata.
final class FabricatedMethodCatalog {
    private let methods: [MethodDescriptor]
    private let modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor]

    init(
        methods: [MethodDescriptor],
        modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor]
    ) {
        self.methods = methods
        self.modifyDispatchDescriptors = modifyDispatchDescriptors
    }

    func method(at slot: Int) -> MethodDescriptor? {
        guard methods.indices.contains(slot) else { return nil }
        return methods[slot]
    }

    func modifyDispatch(forGetterSlot getterSlot: Int) -> ModifyDispatchDescriptor? {
        modifyDispatchDescriptors[getterSlot]
    }
}

/// The transitional public-layer endpoint for compiler-typed witness
/// adapters. Keeping the recorder here prevents the runtime target from
/// depending on TestDoubles recording semantics.
final class StubRecorderInvocationEndpoint: RuntimeInvocationEndpoint,
    @unchecked Sendable
{
    private let recorder: StubRecorder
    /// Runtime-fabricated stubs have a fixed, dense method catalog. Keeping
    /// that catalog next to the semantic endpoint avoids taking the manual
    /// recorder catalog lock for every trampoline call.
    private let fabricatedMethodCatalog: FabricatedMethodCatalog?

    init(recorder: StubRecorder) {
        self.recorder = recorder
        fabricatedMethodCatalog = nil
    }

    init(
        recorder: StubRecorder,
        fabricatedMethodCatalog: FabricatedMethodCatalog
    ) {
        self.recorder = recorder
        self.fabricatedMethodCatalog = fabricatedMethodCatalog
    }

    var invocationMode: RuntimeInvocationMode {
        switch recorder.mode {
            case .normal: .normal
            case .capturing: .capturing
        }
    }

    func prepareDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimePreparedDispatch {
        switch recorder.prepareDispatch(
            method: method(at: request.slot),
            args: request.arguments
        ) {
            case .placeholder:
                return .recording
            case .forwarding:
                return .forwarding
            case .behavior(let behavior):
                return .behavior(runtimeBehavior(behavior))
        }
    }

    func prepareAsyncDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimeAsyncDispatch {
        switch recorder.prepareAsyncDispatch(
            method: method(at: request.slot),
            args: request.arguments
        ) {
            case .placeholder:
                return .recording
            case .immediate(let result):
                return .immediate(result)
            case .suspending(let handler):
                return .suspending(handler)
            case .forwarding:
                return .forwarding
        }
    }

    func modifyDispatch(
        forGetterSlot getterSlot: Int
    ) -> RuntimeModifyDispatch? {
        if let fabricatedMethodCatalog {
            guard
                let dispatch = fabricatedMethodCatalog.modifyDispatch(
                    forGetterSlot: getterSlot
                )
            else {
                return nil
            }
            return RuntimeModifyDispatch(
                getterSlot: dispatch.getterDispatchIndex,
                setterSlot: dispatch.setterDispatchIndex
            )
        }
        guard
            let methods = recorder.modifyDispatchMethods(
                forGetterIndex: getterSlot
            )
        else {
            return nil
        }
        return RuntimeModifyDispatch(
            getterSlot: methods.getter.index,
            setterSlot: methods.setter.index
        )
    }

    func rejectInvocation(at slot: Int) -> Never {
        fatalError(
            "[TestDoubles] A configured runtime invocation endpoint rejected witness slot \(slot)."
        )
    }

    func methodName(at slot: Int) -> String {
        method(at: slot).name
    }

    func recordingAccessorResult(at slot: Int) -> Any {
        let method = method(at: slot)
        func opened<Result>(_ type: Result.Type) -> Any {
            RecordingReturnPlaceholderContext.requiredValue(
                for: type,
                method: method.name
            )
        }
        return _openExistential(method.returnType, do: opened)
    }

    func dispatchTyped<Result>(
        _ request: RuntimeInvocationRequest,
        as resultType: Result.Type
    ) throws -> Result {
        try recorder.dispatchTyped(
            method: method(at: request.slot),
            args: request.arguments,
            as: resultType
        )
    }

    func runtimeResourcesDidPublish(_ resources: AnyObject) {
        recorder.attachRuntimeResources(resources)
    }

    func runtimePayload() -> AnyObject? {
        recorder.makeRuntimePayload()
    }

    func dependentResult(
        for result: Any,
        at slot: Int
    ) -> RuntimeDependentResult {
        let method = method(at: slot)
        if method.kind == .initializer {
            guard let outcome = result as? InitializerDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Initializer handlers must return an initializer outcome. "
                        + "Configure this requirement with when(initializer: ...).thenInitialize(), "
                        + "thenReturnNil(), or then { ... }."
                )
            }
            switch outcome {
                case .success:
                    return .payload
                case .failure:
                    guard method.returnConvention == .optionalSelf else {
                        preconditionFailure(
                            "[TestDoubles] A nonfailable initializer cannot be configured to fail."
                        )
                    }
                    return .nilPayload
            }
        }

        if method.returnConvention == .selfType {
            guard result is SelfResultDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Dynamic Self handlers must complete successfully. "
                        + "Configure this requirement with "
                        + "when(returningSelf: ...).thenReturnValue()."
                )
            }
            return .payload
        }

        guard let outcome = result as? OptionalSelfResultDispatchOutcome else {
            preconditionFailure(
                "[TestDoubles] Optional dynamic Self handlers must return a supported outcome. "
                    + "Configure this requirement with when(returningOptionalSelf: ...)."
                    + "thenReturnValue(), thenReturnNil(), or then { ... }."
            )
        }
        switch outcome {
            case .value: return .payload
            case .nilValue: return .nilPayload
        }
    }

    func recordingResult(at slot: Int) -> RuntimeRecordingResult {
        let method = method(at: slot)
        if method.kind == .initializer || method.returnConvention == .selfType {
            return .payload
        }
        if method.returnConvention == .optionalSelf {
            return .payload
        }
        if let placeholder = RecordingReturnPlaceholderContext.box {
            return .value(placeholder.value)
        }
        return .synthesize
    }

    private func runtimeBehavior(
        _ behavior: StubRecorder.StubEntry.Behavior
    ) -> RuntimeDispatchBehavior {
        switch behavior {
            case .fixed(let result):
                return .fixed(result)
            case .fixedSequence:
                preconditionFailure(
                    "[TestDoubles] A queued stub result was not reserved during dispatch."
                )
            case .immediate(let handler):
                return .immediate(handler)
            case .suspending(let handler):
                return .suspending(handler)
        }
    }

    private func method(at slot: Int) -> MethodDescriptor {
        guard let method = runtimeMethod(at: slot) else {
            rejectInvocation(at: slot)
        }
        return method
    }

    private func runtimeMethod(at slot: Int) -> MethodDescriptor? {
        if let fabricatedMethodCatalog {
            return fabricatedMethodCatalog.method(at: slot)
        }
        return recorder.runtimeMethod(for: slot)
    }
}

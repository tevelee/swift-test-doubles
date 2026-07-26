import InternalRuntimeContract

/// The transitional public-layer endpoint for compiler-typed witness
/// adapters. Keeping the recorder here prevents the runtime target from
/// depending on TestDoubles recording semantics.
final class StubRecorderInvocationEndpoint: RuntimeInvocationEndpoint,
    @unchecked Sendable
{
    private let recorder: StubRecorder

    init(recorder: StubRecorder) {
        self.recorder = recorder
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
        guard
            let methods = recorder.modifyDispatchMethods(
                forGetterIndex: getterSlot
            )
        else {
            return nil
        }
        return RuntimeModifyDispatch(
            getterSlot: methods.getter.slot,
            setterSlot: methods.setter.slot
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

    private func method(at slot: Int) -> RuntimeMethod {
        guard let method = runtimeMethod(at: slot) else {
            rejectInvocation(at: slot)
        }
        return method
    }

    private func runtimeMethod(at slot: Int) -> RuntimeMethod? {
        return recorder.runtimeMethod(for: slot)
    }
}

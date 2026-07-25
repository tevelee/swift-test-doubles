import TestDoublesRuntime

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
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimePreparedDispatch {
        switch recorder.prepareDispatch(method: method, args: args) {
            case .placeholder:
                return .recording
            case .forwarding:
                return .forwarding
            case .behavior(let behavior):
                return .behavior(runtimeBehavior(behavior))
        }
    }

    func prepareAsyncDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeAsyncDispatch {
        switch recorder.prepareAsyncDispatch(method: method, args: args) {
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

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)? {
        recorder.modifyDispatchMethods(forGetterIndex: getterIndex)
    }

    func rejectInvocation(at slot: Int) -> Never {
        fatalError(
            "[TestDoubles] A configured runtime invocation endpoint rejected witness slot \(slot)."
        )
    }

    func recordingAccessorResult(for method: MethodDescriptor) -> Any {
        func opened<Result>(_ type: Result.Type) -> Any {
            RecordingReturnPlaceholderContext.requiredValue(
                for: type,
                method: method.name
            )
        }
        return _openExistential(method.returnType, do: opened)
    }

    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as resultType: Result.Type
    ) throws -> Result {
        try recorder.dispatchTyped(method: method, args: args, as: resultType)
    }

    func runtimePayload() -> AnyObject? {
        recorder.makeRuntimePayload()
    }

    func dependentResult(
        for result: Any,
        method: MethodDescriptor
    ) -> RuntimeDependentResult {
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

    func recordingResult(
        for method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeRecordingResult {
        _ = args
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
}

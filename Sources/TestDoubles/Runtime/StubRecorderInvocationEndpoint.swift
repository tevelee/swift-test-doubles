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
}

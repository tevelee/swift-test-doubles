/// Applies requirement-level result policy before delegating to the ABI
/// transports responsible for values and Swift errors.
enum RuntimeResultEncoder {
    static func encodeDispatchResult(
        _ result: Any,
        for runtimeMethod: PreparedRuntimeMethod,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        let method = runtimeMethod.descriptor
        if case .void = method.returnLayout {
            frame.zeroReturn()
            return
        }
        if method.kind == .initializer {
            guard let outcome = result as? InitializerDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Initializer handlers must return an initializer outcome. "
                        + "Configure this requirement with when(initializer: ...).thenInitialize(), "
                        + "thenReturnNil(), or then { ... }."
                )
            }
            DependentResultEncoder.encodeInitializer(
                outcome,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .selfType {
            guard result is SelfResultDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Dynamic Self handlers must complete successfully. "
                        + "Configure this requirement with "
                        + "when(returningSelf: ...).thenReturnValue()."
                )
            }
            DependentResultEncoder.encodeDynamicSelf(
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .optionalSelf {
            guard let outcome = result as? OptionalSelfResultDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Optional dynamic Self handlers must return a supported outcome. "
                        + "Configure this requirement with when(returningOptionalSelf: ...)."
                        + "thenReturnValue(), thenReturnNil(), or then { ... }."
                )
            }
            DependentResultEncoder.encodeOptionalDynamicSelf(
                outcome,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else {
            DependentResultEncoder.encode(
                result,
                for: method,
                transport: runtimeMethod.resultTransport,
                into: frame
            )
        }
    }

    static func encodeRecordingResult(
        for method: MethodDescriptor,
        args: [Any],
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        RecordingResultEncoder.encode(
            for: method,
            arguments: args,
            recorder: recorder,
            into: frame
        )
    }

    static func encodeFailure(
        _ error: any Error,
        for method: MethodDescriptor,
        typedErrorDestination: UnsafeMutableRawPointer?,
        into frame: TrampolineCallFrame
    ) {
        guard let typedErrorType = method.typedErrorType,
            let typedErrorLayout = method.typedErrorLayout
        else {
            SwiftErrorTransport.encode(error, into: frame)
            return
        }
        SwiftErrorTransport.encodeTyped(
            error,
            expectedType: typedErrorType,
            layout: typedErrorLayout,
            destination: typedErrorDestination,
            usesIndirectResultSlot: method.typedErrorUsesIndirectResultSlot,
            context: "typed error for \(method.name)",
            missingDestinationMessage:
                "[TestDoubles] Missing typed-error result buffer for \(method.name).",
            isAsync: method.isAsync,
            into: frame
        )
    }
}

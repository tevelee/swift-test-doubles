/// Encodes results whose storage depends on the dynamically generated stub.
enum DependentResultEncoder {
    static func encodeDynamicSelf(
        for method: MethodDescriptor,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        guard let payload = recorder.makeRuntimePayload() else {
            fatalError(
                "[TestDoubles] Dynamic Self runtime resources were released before invocation."
            )
        }
        encode(payload, for: method, into: frame)
    }

    static func encodeOptionalDynamicSelf(
        _ outcome: OptionalSelfResultDispatchOutcome,
        for method: MethodDescriptor,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        let payload: StubPayload?
        switch outcome {
            case .value:
                guard let value = recorder.makeRuntimePayload() else {
                    fatalError(
                        "[TestDoubles] Dynamic Self runtime resources were released before invocation."
                    )
                }
                payload = value
            case .nilValue:
                payload = nil
        }
        encode(payload as Any, for: method, into: frame)
    }

    static func encodeInitializer(
        _ outcome: InitializerDispatchOutcome,
        for method: MethodDescriptor,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        switch method.returnConvention {
            case .selfType:
                guard outcome == .success else {
                    preconditionFailure(
                        "[TestDoubles] A nonfailable initializer cannot be configured to fail."
                    )
                }
                guard let payload = recorder.makeRuntimePayload() else {
                    fatalError(
                        "[TestDoubles] Initializer runtime resources were released before invocation."
                    )
                }
                encode(payload, for: method, into: frame)

            case .optionalSelf:
                let payload: StubPayload?
                switch outcome {
                    case .success:
                        guard let value = recorder.makeRuntimePayload() else {
                            fatalError(
                                "[TestDoubles] Initializer runtime resources were released before invocation."
                            )
                        }
                        payload = value
                    case .failure:
                        payload = nil
                }
                encode(payload as Any, for: method, into: frame)

            default:
                preconditionFailure(
                    "[TestDoubles] Initializer \(method.name) does not return dependent Self storage."
                )
        }
    }

    static func encode(
        _ result: Any,
        for method: MethodDescriptor,
        into frame: TrampolineCallFrame
    ) {
        RuntimeValueTransport.encodeReturn(
            result,
            expectedType: method.returnType,
            layout: method.returnLayout,
            context: method.name,
            isAsync: method.isAsync,
            into: frame
        )
    }

    static func encode(
        _ result: Any,
        for method: MethodDescriptor,
        transport: RuntimeResultTransportPlan,
        into frame: TrampolineCallFrame
    ) {
        RuntimeValueTransport.encodeReturn(
            result,
            expectedType: method.returnType,
            layout: method.returnLayout,
            transport: transport,
            context: method.name,
            isAsync: method.isAsync,
            into: frame
        )
    }
}

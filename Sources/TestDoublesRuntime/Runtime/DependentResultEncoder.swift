import InternalRuntimeContract

/// Encodes results whose storage depends on the dynamically generated payload.
package enum DependentResultEncoder {
    package static func encodePayload(
        for method: MethodDescriptor,
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        guard let payload = endpoint.runtimePayload() else {
            fatalError(
                "[TestDoubles] Runtime payload resources were released before invocation."
            )
        }
        encode(payload, for: method, into: frame)
    }

    package static func encodeOptionalPayload(
        _ result: RuntimeDependentResult,
        for method: MethodDescriptor,
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        let payload: AnyObject?
        switch result {
            case .payload:
                guard let value = endpoint.runtimePayload() else {
                    fatalError(
                        "[TestDoubles] Runtime payload resources were released before invocation."
                    )
                }
                payload = value
            case .nilPayload:
                payload = nil
        }
        encode(payload as Any, for: method, into: frame)
    }

    package static func encodeDependentResult(
        _ result: RuntimeDependentResult,
        for method: MethodDescriptor,
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        switch method.returnConvention {
            case .selfType:
                guard result == .payload else {
                    preconditionFailure(
                        "[TestDoubles] A nonfailable runtime initializer cannot produce nil."
                    )
                }
                encodePayload(for: method, endpoint: endpoint, into: frame)

            case .optionalSelf:
                encodeOptionalPayload(
                    result,
                    for: method,
                    endpoint: endpoint,
                    into: frame
                )

            default:
                preconditionFailure(
                    "[TestDoubles] Runtime initializer \(method.name) does not return dependent Self storage."
                )
        }
    }

    package static func encode(
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

    package static func encode(
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

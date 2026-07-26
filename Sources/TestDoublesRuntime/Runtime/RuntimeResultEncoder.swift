import InternalRuntimeContract
import TestDoublesRuntimeMetadata

/// Applies endpoint-selected result policy before delegating to ABI transports.
package enum RuntimeResultEncoder {
    package static func encodeDispatchResult(
        _ result: Any,
        for runtimeMethod: PreparedRuntimeMethod,
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        let method = runtimeMethod.descriptor
        if case .void = method.returnLayout {
            frame.zeroReturn()
            return
        }
        if method.kind == .initializer {
            DependentResultEncoder.encodeDependentResult(
                endpoint.dependentResult(for: result, at: method.index),
                for: method,
                endpoint: endpoint,
                into: frame
            )
        } else if method.returnConvention == .selfType {
            guard endpoint.dependentResult(for: result, at: method.index) == .payload else {
                preconditionFailure(
                    "[TestDoubles] A nonoptional runtime Self result cannot produce nil."
                )
            }
            DependentResultEncoder.encodePayload(
                for: method,
                endpoint: endpoint,
                into: frame
            )
        } else if method.returnConvention == .optionalSelf {
            DependentResultEncoder.encodeOptionalPayload(
                endpoint.dependentResult(for: result, at: method.index),
                for: method,
                endpoint: endpoint,
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

    package static func encodeRecordingResult(
        for method: MethodDescriptor,
        args: [Any],
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        RecordingResultEncoder.encode(
            for: method,
            arguments: args,
            endpoint: endpoint,
            into: frame
        )
    }

    package static func encodeFailure(
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

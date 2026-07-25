import Echo

/// Synthesizes safe temporary results while a requirement is being recorded.
package enum RecordingResultEncoder {
    package static func encode(
        for method: MethodDescriptor,
        arguments: [Any],
        endpoint: any RuntimeInvocationEndpoint,
        into frame: TrampolineCallFrame
    ) {
        switch endpoint.recordingResult(for: method, args: arguments) {
            case .payload:
                DependentResultEncoder.encodePayload(
                    for: method,
                    endpoint: endpoint,
                    into: frame
                )

            case .nilPayload:
                DependentResultEncoder.encodeOptionalPayload(
                    .nilPayload,
                    for: method,
                    endpoint: endpoint,
                    into: frame
                )

            case .value(let value):
                DependentResultEncoder.encode(value, for: method, into: frame)

            case .synthesize:
                encodePlaceholder(
                    for: method,
                    arguments: arguments,
                    into: frame
                )
        }
    }

    private static func encodePlaceholder(
        for method: MethodDescriptor,
        arguments: [Any],
        into frame: TrampolineCallFrame
    ) {
        let layout = method.returnLayout
        frame.zeroReturn()

        switch layout {
            case .void, .floatingPoint:
                return
            case .integer(let words):
                if method.returnType == String.self {
                    DependentResultEncoder.encode("", for: method, into: frame)
                } else if encodeInitializedPlaceholder(
                    type: method.returnType,
                    for: method,
                    into: frame
                ) {
                    return
                } else if words > 1 {
                    frame.storeGeneralPurposeReturn(0, at: 1)
                }
            case .aggregate(let parts):
                let returnType = method.returnType
                guard PlaceholderValue.canInitialize(type: returnType) else {
                    fatalError(unsupportedPlaceholderMessage(for: method))
                }
                initializeAggregatePlaceholder(
                    type: returnType,
                    parts: parts,
                    into: frame
                )
            case .indirect:
                encodeIndirectPlaceholder(
                    for: method,
                    arguments: arguments,
                    into: frame
                )
        }
    }

    private static func encodeIndirectPlaceholder(
        for method: MethodDescriptor,
        arguments: [Any],
        into frame: TrampolineCallFrame
    ) {
        let destinationWord = frame.indirectResultAddress
        guard
            let destination = UnsafeMutableRawPointer(
                bitPattern: destinationWord
            )
        else {
            fatalError(
                "[TestDoubles] Cannot record indirect-return requirement \(method.name) without return metadata."
            )
        }
        let returnType = method.returnType
        #if arch(x86_64)
            if method.isAsync == false {
                frame.storeGeneralPurposeReturn(destinationWord)
            }
        #endif
        if reflect(returnType) is ExistentialMetadata,
            let index = method.arguments.firstIndex(where: {
                $0.value.type == returnType
            }),
            arguments.indices.contains(index)
        {
            RuntimeValueTransport.copyValue(
                arguments[index],
                expectedType: returnType,
                to: destination
            )
            return
        }
        guard
            PlaceholderValue.initialize(
                type: returnType,
                at: destination
            )
        else {
            fatalError(unsupportedPlaceholderMessage(for: method))
        }
    }

    private static func encodeInitializedPlaceholder(
        type: Any.Type,
        for method: MethodDescriptor,
        into frame: TrampolineCallFrame
    ) -> Bool {
        let storage = ManagedValueBuffer(type: type)
        guard PlaceholderValue.initialize(type: type, at: storage.storage) else {
            return false
        }
        storage.markInitialized()
        let value = boxValue(type: type, source: storage.storage)
        storage.destroyInitializedValue()
        DependentResultEncoder.encode(value, for: method, into: frame)
        return true
    }

    private static func initializeAggregatePlaceholder(
        type: Any.Type,
        parts: [DirectValuePart],
        into frame: TrampolineCallFrame
    ) {
        let temporary = ManagedValueBuffer(
            type: type,
            minimumByteCount: 16
        )
        guard PlaceholderValue.initialize(type: type, at: temporary.storage) else {
            fatalError(
                "[TestDoubles] Stub cannot synthesize a recording placeholder for \(type)."
            )
        }
        temporary.markInitialized()
        RuntimeValueTransport.encodeAggregateReturn(
            parts: parts,
            from: temporary.storage,
            into: frame
        )
        temporary.markTransferred()
    }

    private static func unsupportedPlaceholderMessage(
        for method: MethodDescriptor
    ) -> String {
        "[TestDoubles] Stub cannot synthesize a recording result for \(method.returnType). "
            + "Pass a valid value with when(returning:_:) or verify(_:returning:_:) "
            + "for \(method.name)."
    }
}

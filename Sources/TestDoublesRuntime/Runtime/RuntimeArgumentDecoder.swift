import EchoRuntimeSupport
import TestDoublesRuntimeMetadata

package struct RuntimeArgumentSpec: Sendable {
    package let type: Any.Type
    package let convention: WitnessValueConvention
    package let layout: ABIClass
    package let ownership: WitnessArgumentOwnership
}

package struct RuntimeArgumentDecodingPlan: Sendable {
    package enum DiagnosticContext: Sendable {
        case dynamicFunction
        case witness(String)

        package var missingIndirectArgument: String {
            switch self {
                case .dynamicFunction:
                    "[TestDoubles] Missing indirect dynamic function argument storage."
                case .witness(let name):
                    "[TestDoubles] Missing indirect argument storage for \(name)."
            }
        }

        package var missingTypedErrorDestination: String {
            switch self {
                case .dynamicFunction:
                    "[TestDoubles] Missing indirect dynamic function typed-error storage."
                case .witness(let name):
                    "[TestDoubles] Missing typed-error result buffer for \(name)."
            }
        }
    }

    package let arguments: [RuntimeArgumentSpec]
    package let argumentLocations: [[CallFrameArgumentLocation]]
    package let genericParameterMetadataLocations: [CallFrameArgumentLocation]
    package let typedErrorDestinationLocation: CallFrameArgumentLocation?
    package let diagnosticContext: DiagnosticContext

    package static func witness(
        method: MethodDescriptor,
        transport: WitnessCallTransportPlan,
        consumeOwnedArguments: Bool
    ) -> Self {
        Self(
            arguments: method.arguments.map {
                RuntimeArgumentSpec(
                    type: $0.value.type,
                    convention: $0.value.convention,
                    layout: $0.value.layout,
                    ownership:
                        consumeOwnedArguments ? $0.ownership : .borrowed
                )
            },
            argumentLocations: transport.argumentLocations,
            genericParameterMetadataLocations:
                transport.genericParameterMetadataLocations,
            typedErrorDestinationLocation:
                transport.typedErrorDestinationLocation,
            diagnosticContext: .witness(method.name)
        )
    }
}

package enum RuntimeArgumentDecoder {
    package static func decode(
        for runtimeMethod: PreparedRuntimeMethod,
        from frame: TrampolineCallFrame,
        consumeOwnedArguments: Bool = true
    ) -> DecodedArguments {
        if consumeOwnedArguments {
            return decode(runtimeMethod.consumingDecodingPlan, from: frame)
        }
        return decode(runtimeMethod.borrowedDecodingPlan, from: frame)
    }

    package static func decode(
        for method: MethodDescriptor,
        from frame: TrampolineCallFrame,
        initialGeneralPurposeOffset: Int = 0,
        consumeOwnedArguments: Bool = true
    ) -> DecodedArguments {
        let transport = WitnessCallTransportPlan(
            method: method,
            initialGeneralPurposeOffset: initialGeneralPurposeOffset
        )
        return decode(
            RuntimeArgumentDecodingPlan.witness(
                method: method,
                transport: transport,
                consumeOwnedArguments: consumeOwnedArguments
            ),
            from: frame
        )
    }

    package static func decode(
        _ plan: borrowing RuntimeArgumentDecodingPlan,
        from frame: TrampolineCallFrame
    ) -> DecodedArguments {
        precondition(
            plan.arguments.count == plan.argumentLocations.count,
            "[TestDoubles] Runtime argument metadata and call-frame locations diverged."
        )
        var values: [Any] = []
        values.reserveCapacity(plan.arguments.count)

        for (argument, locations) in zip(
            plan.arguments,
            plan.argumentLocations
        ) {
            let consumesArgument = argument.ownership == .owned
            switch argument.layout {
                case .void:
                    precondition(locations.isEmpty)
                    if argument.type == Void.self {
                        values.append(())
                    } else {
                        let storage = ValueStorage.allocate(for: argument.type)
                        defer { storage.deallocate() }
                        storage.initializeMemory(
                            as: UInt8.self,
                            repeating: 0,
                            count: ValueStorage.byteCount(for: argument.type)
                        )
                        values.append(
                            copyArgument(
                                type: argument.type,
                                source: storage,
                                consuming: consumesArgument
                            )
                        )
                    }

                case .floatingPoint:
                    precondition(locations.count == 1)
                    let bits = frame.scalarBits(at: locations[0])
                    if argument.type == Float.self {
                        var raw = UInt32(truncatingIfNeeded: bits)
                        values.append(
                            copyArgument(
                                type: Float.self,
                                source: &raw,
                                consuming: consumesArgument
                            ))
                    } else {
                        var raw = bits
                        values.append(
                            copyArgument(
                                type: argument.type,
                                source: &raw,
                                consuming: consumesArgument
                            ))
                    }

                case .integer(let words):
                    precondition(locations.count == words)
                    var storage = (UInt64(0), UInt64(0))
                    withUnsafeMutableBytes(of: &storage) { bytes in
                        for location in locations {
                            bytes.storeBytes(
                                of: frame.scalarBits(at: location),
                                toByteOffset: location.valueOffset,
                                as: UInt64.self
                            )
                        }
                    }
                    values.append(
                        withUnsafeMutablePointer(to: &storage) {
                            copyArgument(
                                type: argument.type,
                                source: UnsafeMutableRawPointer($0),
                                consuming: consumesArgument
                            )
                        })

                case .aggregate(let parts):
                    values.append(
                        decodeAggregateArgument(
                            type: argument.type,
                            parts: parts,
                            locations: locations,
                            from: frame,
                            consuming: consumesArgument
                        ))

                case .indirect:
                    precondition(locations.count == 1)
                    let address = UInt(frame.scalarBits(at: locations[0]))
                    guard let source = UnsafeMutableRawPointer(bitPattern: address) else {
                        fatalError(plan.diagnosticContext.missingIndirectArgument)
                    }
                    let runtimeType: Any.Type
                    if case .methodGenericParameter(let index) = argument.convention {
                        runtimeType = genericParameterMetadataType(
                            at: index,
                            in: plan.genericParameterMetadataLocations,
                            from: frame
                        )
                    } else {
                        runtimeType = argument.type
                    }
                    values.append(
                        copyArgument(
                            type: runtimeType,
                            source: source,
                            consuming: consumesArgument
                        ))
            }
        }

        let typedErrorDestination: UnsafeMutableRawPointer?
        if let location = plan.typedErrorDestinationLocation {
            let address = UInt(frame.scalarBits(at: location))
            guard let destination = UnsafeMutableRawPointer(bitPattern: address) else {
                fatalError(plan.diagnosticContext.missingTypedErrorDestination)
            }
            typedErrorDestination = destination
        } else {
            typedErrorDestination = nil
        }

        return DecodedArguments(
            values: values,
            typedErrorDestination: typedErrorDestination
        )
    }

    private static func decodeAggregateArgument(
        type: Any.Type,
        parts: [DirectValuePart],
        locations: [CallFrameArgumentLocation],
        from frame: TrampolineCallFrame,
        consuming: Bool
    ) -> Any {
        precondition(parts.count == locations.count)
        let temporary = ValueStorage.allocate(for: type)
        defer { temporary.deallocate() }
        temporary.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: ValueStorage.byteCount(for: type)
        )
        for (part, location) in zip(parts, locations) {
            precondition(part.offset == location.valueOffset)
            frame.copyArgumentBytes(
                at: location,
                into: temporary + part.offset
            )
        }
        return copyArgument(
            type: type,
            source: temporary,
            consuming: consuming
        )
    }

    /// Reads the caller-supplied type metadata for one requirement-level
    /// generic parameter out of its reserved call-frame register.
    private static func genericParameterMetadataType(
        at index: Int,
        in locations: [CallFrameArgumentLocation],
        from frame: TrampolineCallFrame
    ) -> Any.Type {
        precondition(
            locations.indices.contains(index),
            "[TestDoubles] Missing call-frame location for requirement-level generic parameter \(index)."
        )
        let bits = UInt(frame.scalarBits(at: locations[index]))
        guard let metadata = UnsafeRawPointer(bitPattern: bits) else {
            fatalError(
                "[TestDoubles] Missing runtime metadata for requirement-level generic parameter \(index)."
            )
        }
        return unsafeBitCast(metadata, to: Any.Type.self)
    }

    /// Copies an ABI argument into recorder-owned `Any` storage, then consumes
    /// the caller-owned source when its witness convention is owned. Borrowed
    /// arguments are never destroyed here.
    private static func copyArgument(
        type: Any.Type,
        source: UnsafeMutableRawPointer,
        consuming: Bool
    ) -> Any {
        let value = FunctionReabstraction.boxDirectValue(
            type: type,
            source: source
        )
        if consuming {
            ValueOperations.destroy(type, at: source)
        }
        return value
    }
}

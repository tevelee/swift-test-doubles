import Echo

/// Recorder-owned values decoded from one witness call, plus any distinct
/// caller-owned typed-error result storage required by the signature.
struct DecodedArguments {
    let values: [Any]
    let typedErrorDestination: UnsafeMutableRawPointer?
}

struct RuntimeArgumentSpec: Sendable {
    let type: Any.Type
    let layout: ABIClass
    let ownership: WitnessArgumentOwnership
}

struct RuntimeArgumentDecodingPlan: Sendable {
    enum DiagnosticContext: Sendable {
        case dynamicFunction
        case witness(String)

        var missingIndirectArgument: String {
            switch self {
                case .dynamicFunction:
                    "[TestDoubles] Missing indirect dynamic function argument storage."
                case .witness(let name):
                    "[TestDoubles] Missing indirect argument storage for \(name)."
            }
        }

        var missingTypedErrorDestination: String {
            switch self {
                case .dynamicFunction:
                    "[TestDoubles] Missing indirect dynamic function typed-error storage."
                case .witness(let name):
                    "[TestDoubles] Missing typed-error result buffer for \(name)."
            }
        }
    }

    let arguments: [RuntimeArgumentSpec]
    let argumentLocations: [[CallFrameArgumentLocation]]
    let typedErrorDestinationLocation: CallFrameArgumentLocation?
    let diagnosticContext: DiagnosticContext

    static func witness(
        method: MethodDescriptor,
        transport: WitnessCallTransportPlan,
        consumeOwnedArguments: Bool
    ) -> Self {
        Self(
            arguments: method.arguments.map {
                RuntimeArgumentSpec(
                    type: $0.value.type,
                    layout: $0.value.layout,
                    ownership:
                        consumeOwnedArguments ? $0.ownership : .borrowed
                )
            },
            argumentLocations: transport.argumentLocations,
            typedErrorDestinationLocation:
                transport.typedErrorDestinationLocation,
            diagnosticContext: .witness(method.name)
        )
    }
}

enum RuntimeArgumentDecoder {
    static func decodeDynamicFunctionArguments(
        _ types: [Any.Type],
        typedErrorUsesIndirectResultSlot: Bool,
        initialGeneralPurposeOffset: Int = 0,
        from frame: TrampolineCallFrame
    ) -> DecodedArguments {
        let arguments = types.map {
            RuntimeArgumentSpec(
                type: $0,
                layout: abiClass(for: $0),
                ownership: .borrowed
            )
        }
        let locationPlan = CallFrameArgumentLocationPlan(
            arguments: arguments.map {
                CallFrameArgumentShape(type: $0.type, layout: $0.layout)
            },
            initialGeneralPurposeOffset: initialGeneralPurposeOffset,
            trailingGeneralPurposeWordCount:
                typedErrorUsesIndirectResultSlot ? 1 : 0
        )
        return decode(
            RuntimeArgumentDecodingPlan(
                arguments: arguments,
                argumentLocations: locationPlan.arguments,
                typedErrorDestinationLocation:
                    locationPlan.trailingGeneralPurpose.first,
                diagnosticContext: .dynamicFunction
            ),
            from: frame
        )
    }

    static func decode(
        for runtimeMethod: PreparedRuntimeMethod,
        from frame: TrampolineCallFrame,
        consumeOwnedArguments: Bool = true
    ) -> DecodedArguments {
        if consumeOwnedArguments {
            return decode(runtimeMethod.consumingDecodingPlan, from: frame)
        }
        return decode(runtimeMethod.borrowedDecodingPlan, from: frame)
    }

    static func decode(
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

    private static func decode(
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
                    values.append(())

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
                    values.append(
                        copyArgument(
                            type: argument.type,
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
        let metadata = reflect(type)
        let temporary = metadata.allocateValueBuffer()
        defer { temporary.deallocate() }
        temporary.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: metadata.valueBufferByteCount()
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
            reflect(type).vwt.destroy(source)
        }
        return value
    }
}

func boxValue(type: Any.Type, source: UnsafeMutableRawPointer) -> Any {
    func boxOpenedValue<T>(_ type: T.Type) -> Any {
        source.assumingMemoryBound(to: T.self).pointee
    }
    return _openExistential(type, do: boxOpenedValue)
}

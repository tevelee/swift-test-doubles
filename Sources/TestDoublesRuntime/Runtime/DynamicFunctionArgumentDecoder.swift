import EchoRuntimeSupport
import TestDoublesRuntimeMetadata

/// The decoded direct-call arguments needed to invoke a dynamically bridged
/// generic function, plus optional typed-error storage supplied by its caller.
package struct DecodedArguments {
    package let values: [Any]
    package let typedErrorDestination: UnsafeMutableRawPointer?

    package init(
        values: [Any],
        typedErrorDestination: UnsafeMutableRawPointer?
    ) {
        self.values = values
        self.typedErrorDestination = typedErrorDestination
    }
}

/// Immutable direct-call transport for a dynamically bridged function.
///
/// The plan is constructed with the bridge context and reused for every
/// invocation. That keeps metadata classification and argument-location
/// planning off the trampoline's hot path.
package struct DynamicFunctionArgumentDecodingPlan: Sendable {
    private struct Argument: Sendable {
        let type: Any.Type
        let layout: ABIClass
    }

    private let arguments: [Argument]
    private let argumentLocations: [[CallFrameArgumentLocation]]
    private let typedErrorDestinationLocation: CallFrameArgumentLocation?

    package init(
        parameterTypes: [Any.Type],
        typedErrorUsesIndirectResultSlot: Bool,
        initialGeneralPurposeOffset: Int = 0
    ) {
        arguments = parameterTypes.map {
            Argument(type: $0, layout: abiClass(for: $0))
        }
        let locationPlan = CallFrameArgumentLocationPlan(
            arguments: arguments.map {
                CallFrameArgumentShape(type: $0.type, layout: $0.layout)
            },
            initialGeneralPurposeOffset: initialGeneralPurposeOffset,
            trailingGeneralPurposeWordCount:
                typedErrorUsesIndirectResultSlot ? 1 : 0
        )
        argumentLocations = locationPlan.arguments
        typedErrorDestinationLocation = locationPlan.trailingGeneralPurpose.first
    }

    package func decode(from frame: TrampolineCallFrame) -> DecodedArguments {
        precondition(
            arguments.count == argumentLocations.count,
            "[TestDoubles] Dynamic function argument metadata and call-frame locations diverged."
        )
        var values: [Any] = []
        values.reserveCapacity(arguments.count)

        for (argument, locations) in zip(arguments, argumentLocations) {
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
                            boxDirectValue(
                                type: argument.type,
                                source: storage
                            )
                        )
                    }

                case .floatingPoint:
                    precondition(locations.count == 1)
                    let bits = frame.scalarBits(at: locations[0])
                    if argument.type == Float.self {
                        var raw = UInt32(truncatingIfNeeded: bits)
                        values.append(boxDirectValue(type: Float.self, source: &raw))
                    } else {
                        var raw = bits
                        values.append(
                            boxDirectValue(type: argument.type, source: &raw)
                        )
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
                            boxDirectValue(
                                type: argument.type,
                                source: UnsafeMutableRawPointer($0)
                            )
                        })

                case .aggregate(let parts):
                    values.append(
                        decodeAggregateArgument(
                            type: argument.type,
                            parts: parts,
                            locations: locations,
                            from: frame
                        ))

                case .indirect:
                    precondition(locations.count == 1)
                    let address = UInt(frame.scalarBits(at: locations[0]))
                    guard let source = UnsafeMutableRawPointer(bitPattern: address) else {
                        fatalError(
                            "[TestDoubles] Missing indirect dynamic function argument storage."
                        )
                    }
                    values.append(boxDirectValue(type: argument.type, source: source))
            }
        }

        let typedErrorDestination: UnsafeMutableRawPointer?
        if let location = typedErrorDestinationLocation {
            let address = UInt(frame.scalarBits(at: location))
            guard let destination = UnsafeMutableRawPointer(bitPattern: address) else {
                fatalError(
                    "[TestDoubles] Missing indirect dynamic function typed-error storage."
                )
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

    private func decodeAggregateArgument(
        type: Any.Type,
        parts: [DirectValuePart],
        locations: [CallFrameArgumentLocation],
        from frame: TrampolineCallFrame
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
            frame.copyArgumentBytes(at: location, into: temporary + part.offset)
        }
        return boxDirectValue(type: type, source: temporary)
    }

    private func boxDirectValue(
        type: Any.Type,
        source: UnsafeMutableRawPointer
    ) -> Any {
        FunctionReabstraction.boxDirectValue(type: type, source: source)
    }
}

package func boxValue(type: Any.Type, source: UnsafeMutableRawPointer) -> Any {
    func boxOpenedValue<T>(_ type: T.Type) -> Any {
        source.assumingMemoryBound(to: T.self).pointee
    }
    return _openExistential(type, do: boxOpenedValue)
}

package protocol AsyncTrampolineDispatchState: AnyObject, Sendable {
    func run() async
    func finish(into frame: TrampolineCallFrame)
}

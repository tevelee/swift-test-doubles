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
    let initialGeneralPurposeOffset: Int
    let hasTypedErrorDestination: Bool
    let diagnosticContext: DiagnosticContext
}

enum RuntimeArgumentDecoder {
    static func decodeDynamicFunctionArguments(
        _ types: [Any.Type],
        typedErrorUsesIndirectResultSlot: Bool,
        initialGeneralPurposeOffset: Int = 0,
        from frame: TrampolineCallFrame
    ) -> DecodedArguments {
        decode(
            RuntimeArgumentDecodingPlan(
                arguments: types.map {
                    RuntimeArgumentSpec(
                        type: $0,
                        layout: abiClass(for: $0),
                        ownership: .borrowed
                    )
                },
                initialGeneralPurposeOffset: initialGeneralPurposeOffset,
                hasTypedErrorDestination: typedErrorUsesIndirectResultSlot,
                diagnosticContext: .dynamicFunction
            ),
            from: frame
        )
    }

    static func decode(
        for method: MethodDescriptor,
        from frame: TrampolineCallFrame,
        initialGeneralPurposeOffset: Int = 0
    ) -> DecodedArguments {
        let hasAsyncIndirectResult: Bool
        if method.isAsync, case .indirect = method.result.layout {
            hasAsyncIndirectResult = true
        } else {
            hasAsyncIndirectResult = false
        }
        return decode(
            RuntimeArgumentDecodingPlan(
                arguments: method.arguments.map {
                    RuntimeArgumentSpec(
                        type: $0.value.type,
                        layout: $0.value.layout,
                        ownership: $0.ownership
                    )
                },
                initialGeneralPurposeOffset: initialGeneralPurposeOffset
                    + (hasAsyncIndirectResult ? 1 : 0),
                hasTypedErrorDestination: method.typedErrorUsesIndirectResultSlot,
                diagnosticContext: .witness(method.name)
            ),
            from: frame
        )
    }

    private static func decode(
        _ plan: RuntimeArgumentDecodingPlan,
        from frame: TrampolineCallFrame
    ) -> DecodedArguments {
        var cursor = TrampolineCallFrame.ArgumentCursor(
            initialGeneralPurposeOffset: plan.initialGeneralPurposeOffset
        )
        var values: [Any] = []
        values.reserveCapacity(plan.arguments.count)

        for argument in plan.arguments {
            let consumesArgument = argument.ownership == .owned
            switch argument.layout {
                case .void:
                    values.append(())

                case .floatingPoint:
                    let bits = frame.takeFloatingPointWord(&cursor)
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
                    var storage = (UInt64(0), UInt64(0))
                    withUnsafeMutableBytes(of: &storage) { bytes in
                        for word in 0 ..< words {
                            bytes.storeBytes(
                                of: UInt64(frame.takeGeneralPurposeWord(&cursor)),
                                toByteOffset: word * 8,
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
                            cursor: &cursor,
                            from: frame,
                            consuming: consumesArgument
                        ))

                case .indirect:
                    let address = frame.takeGeneralPurposeWord(&cursor)
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
        if plan.hasTypedErrorDestination {
            let address = frame.takeGeneralPurposeWord(&cursor)
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
        cursor: inout TrampolineCallFrame.ArgumentCursor,
        from frame: TrampolineCallFrame,
        consuming: Bool
    ) -> Any {
        let metadata = reflect(type)
        let temporary = metadata.allocateValueBuffer()
        temporary.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: metadata.valueBufferByteCount()
        )
        for part in parts {
            let value: UInt64
            switch part.register {
                case .gp:
                    value = UInt64(frame.takeGeneralPurposeWord(&cursor))
                case .fp:
                    value = frame.takeFloatingPointWord(&cursor)
            }
            part.store(value, into: temporary)
        }
        let boxed = copyArgument(
            type: type,
            source: temporary,
            consuming: consuming
        )
        temporary.deallocate()
        return boxed
    }

    /// Copies an ABI argument into recorder-owned `Any` storage, then consumes
    /// the caller-owned source when its witness convention is owned. Borrowed
    /// arguments are never destroyed here.
    private static func copyArgument(
        type: Any.Type,
        source: UnsafeMutableRawPointer,
        consuming: Bool
    ) -> Any {
        let value: Any
        value = FunctionReabstraction.boxDirectValue(type: type, source: source)
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

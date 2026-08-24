import Echo
import EchoRuntimeSupport

/// Moves Swift values across the captured trampoline frame according to a
/// previously validated ABI layout.
package enum RuntimeValueTransport {
    package static func optionalType(wrapping type: Any.Type) -> Any.Type {
        func open<Wrapped>(_ type: Wrapped.Type) -> Any.Type {
            Optional<Wrapped>.self
        }
        return _openExistential(type, do: open)
    }

    package static func copyValue(
        _ result: Any,
        expectedType: Any.Type?,
        to destination: UnsafeMutableRawPointer
    ) {
        withProjectedValue(of: result) { actualType, source in
            let type = expectedType ?? actualType
            if let expectedType, actualType != expectedType {
                func copyCastedResult<T>(_ type: T.Type) {
                    guard let value = result as? T else {
                        preconditionFailure(
                            "[TestDoubles] Type mismatch: expected \(expectedType), got \(actualType)."
                        )
                    }
                    withUnsafePointer(to: value) {
                        ValueOperations.initializeCopy(
                            of: type,
                            from: UnsafeRawPointer($0),
                            to: destination
                        )
                    }
                }
                _openExistential(expectedType, do: copyCastedResult)
                return
            }
            ValueOperations.initializeCopy(
                of: type,
                from: source,
                to: destination
            )
        }
    }

    package static func initializeDirectValue(
        _ value: Any,
        expectedType: Any.Type,
        to destination: UnsafeMutableRawPointer
    ) {
        initializeDirectValue(
            value,
            expectedType: expectedType,
            transport: RuntimeResultTransportPlan(resultType: expectedType),
            at: destination
        )
    }

    package static func initializeDirectValue(
        _ value: Any,
        expectedType: Any.Type,
        transport: RuntimeResultTransportPlan,
        at destination: UnsafeMutableRawPointer
    ) {
        if transport.requiresFunctionReabstraction,
            FunctionReabstraction.initializeDirectReturn(
                value,
                expectedType: expectedType,
                prepared: transport.functionReabstraction,
                at: destination
            )
        {
            return
        }
        copyValue(value, expectedType: expectedType, to: destination)
    }

    package static func encodeReturn(
        _ value: Any,
        expectedType: Any.Type,
        layout: ABIClass,
        context: String,
        isAsync: Bool,
        into frame: TrampolineCallFrame
    ) {
        encodeReturn(
            value,
            expectedType: expectedType,
            layout: layout,
            transport: RuntimeResultTransportPlan(resultType: expectedType),
            context: context,
            isAsync: isAsync,
            into: frame
        )
    }

    package static func encodeReturn(
        _ value: Any,
        expectedType: Any.Type,
        layout: ABIClass,
        transport: RuntimeResultTransportPlan,
        context: String,
        isAsync: Bool,
        into frame: TrampolineCallFrame
    ) {
        frame.zeroReturn()

        switch layout {
            case .void:
                return

            case .floatingPoint, .integer, .aggregate:
                withCopiedValue(
                    value,
                    expectedType: expectedType,
                    transport: transport
                ) { source in
                    encodeBorrowedDirectValue(
                        from: source,
                        layout: layout,
                        into: frame
                    )
                }

            case .indirect:
                let destinationWord = frame.indirectResultAddress
                guard
                    let destination = UnsafeMutableRawPointer(
                        bitPattern: destinationWord
                    )
                else {
                    fatalError(
                        "[TestDoubles] Missing indirect return buffer for \(context)."
                    )
                }
                initializeDirectValue(
                    value,
                    expectedType: expectedType,
                    transport: transport,
                    at: destination
                )
                #if arch(x86_64)
                    if isAsync == false {
                        frame.storeGeneralPurposeReturn(destinationWord)
                    }
                #endif
        }
    }

    /// Copies an already initialized value's bits into direct result registers
    /// without retaining or destroying the source. The caller defines whether
    /// those bits transfer ownership or remain borrowed and keeps `source`
    /// alive for the required lifetime.
    package static func encodeBorrowedDirectValue(
        from source: UnsafeRawPointer,
        layout: ABIClass,
        into frame: TrampolineCallFrame
    ) {
        frame.zeroReturn()
        switch layout {
            case .void:
                return
            case .floatingPoint:
                frame.storeFloatingPointReturn(
                    UInt(source.loadUnaligned(as: UInt64.self))
                )
            case .integer(let words):
                guard words <= TrampolineCallFrame.generalPurposeReturnCount else {
                    fatalError(
                        "[TestDoubles] Direct integer return uses too many general-purpose registers."
                    )
                }
                for index in 0 ..< words {
                    frame.storeGeneralPurposeReturn(
                        UInt(
                            (source + index * MemoryLayout<UInt64>.size)
                                .loadUnaligned(as: UInt64.self)
                        ),
                        at: index
                    )
                }
            case .aggregate(let parts):
                encodeAggregateReturn(
                    parts: parts,
                    from: source,
                    into: frame
                )
            case .indirect:
                preconditionFailure(
                    "[TestDoubles] Indirect results must be initialized in caller storage."
                )
        }
    }

    package static func encodeAggregateReturn(
        parts: [DirectValuePart],
        from source: UnsafeRawPointer,
        into frame: TrampolineCallFrame
    ) {
        var generalPurpose = 0
        var floatingPoint = 0
        for part in parts {
            switch part.register {
                case .gp:
                    guard
                        generalPurpose
                            < TrampolineCallFrame.generalPurposeReturnCount
                    else {
                        fatalError(
                            "[TestDoubles] Direct aggregate return uses too many general-purpose registers."
                        )
                    }
                    frame.storeGeneralPurposeReturn(
                        UInt(truncatingIfNeeded: part.load(from: source)),
                        at: generalPurpose
                    )
                    generalPurpose += 1
                case .fp:
                    guard
                        floatingPoint
                            < TrampolineCallFrame.floatingPointReturnCount
                    else {
                        fatalError(
                            "[TestDoubles] Direct aggregate return uses too many floating-point registers."
                        )
                    }
                    frame.storeVectorReturn(
                        from: source + part.offset,
                        byteCount: part.byteCount,
                        at: floatingPoint
                    )
                    floatingPoint += 1
            }
        }
    }

    private static func withCopiedValue(
        _ result: Any,
        expectedType: Any.Type?,
        transport: RuntimeResultTransportPlan,
        _ body: (UnsafeMutableRawPointer) -> Void
    ) {
        let type =
            expectedType
            ?? withProjectedValue(of: result) { type, _ in
                type
            }
        let metadata = reflect(type)
        let byteCount = max(metadata.vwt.size, 16)
        let alignment = max(
            metadata.vwt.flags.alignment,
            MemoryLayout<UInt>.alignment
        )
        withUnsafeTemporaryAllocation(
            byteCount: byteCount,
            alignment: alignment
        ) { temporary in
            let storage = temporary.baseAddress!
            storage.initializeMemory(
                as: UInt8.self,
                repeating: 0,
                count: byteCount
            )
            if let expectedType {
                initializeDirectValue(
                    result,
                    expectedType: expectedType,
                    transport: transport,
                    at: storage
                )
            } else {
                copyValue(result, expectedType: nil, to: storage)
            }
            body(storage)
            // Direct return registers now own the initialized bits. Releasing
            // the stack allocation must not destroy the transferred value.
        }
    }
}

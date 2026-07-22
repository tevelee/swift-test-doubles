import Echo

/// Moves Swift values across the captured trampoline frame according to a
/// previously validated ABI layout.
enum RuntimeValueTransport {
    static func copyValue(
        _ result: Any,
        expectedType: Any.Type?,
        to destination: UnsafeMutableRawPointer
    ) {
        var container = Echo.container(for: result)
        let actual = container.metadata
        let metadata = expectedType.map(reflect) ?? actual
        if let expectedType, actual.type != expectedType {
            func copyCastedResult<T>(_ type: T.Type) {
                guard let value = result as? T else {
                    preconditionFailure(
                        "[TestDoubles] Type mismatch: expected \(expectedType), got \(actual.type)."
                    )
                }
                withUnsafePointer(to: value) {
                    metadata.vwt.initializeWithCopy(
                        destination,
                        UnsafeMutableRawPointer(mutating: $0)
                    )
                }
            }
            _openExistential(expectedType, do: copyCastedResult)
            return
        }
        metadata.vwt.initializeWithCopy(
            destination,
            UnsafeMutableRawPointer(mutating: container.projectValue())
        )
    }

    static func initializeDirectValue(
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

    static func initializeDirectValue(
        _ value: Any,
        expectedType: Any.Type,
        transport: RuntimeResultTransportPlan,
        at destination: UnsafeMutableRawPointer
    ) {
        if transport.requiresFunctionReabstraction,
            FunctionReabstraction.initializeDirectReturn(
                value,
                expectedType: expectedType,
                at: destination
            )
        {
            return
        }
        copyValue(value, expectedType: expectedType, to: destination)
    }

    static func encodeReturn(
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

    static func encodeReturn(
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
    static func encodeBorrowedDirectValue(
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

    static func encodeAggregateReturn(
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
        let type = expectedType ?? Echo.container(for: result).metadata.type
        let temporary = ManagedValueBuffer(
            type: type,
            minimumByteCount: 16
        )
        temporary.zeroBorrowedBytes()
        if let expectedType {
            initializeDirectValue(
                result,
                expectedType: expectedType,
                transport: transport,
                at: temporary.storage
            )
        } else {
            copyValue(result, expectedType: nil, to: temporary.storage)
        }
        temporary.markInitialized()
        body(temporary.storage)
        temporary.markTransferred()
    }
}

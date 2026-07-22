import CTestDoublesTrampoline
import Echo

enum RuntimeResultEncoder {
    static func encodeDispatchResult(
        _ result: Any,
        for method: MethodDescriptor,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        if method.kind == .initializer {
            guard let outcome = result as? InitializerDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Initializer handlers must return an initializer outcome. "
                        + "Configure this requirement with when(initializer: ...).thenInitialize(), "
                        + "thenReturnNil(), or then { ... }."
                )
            }
            encodeInitializerOutcome(
                outcome,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .selfType {
            guard result is SelfResultDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Dynamic Self handlers must complete successfully. "
                        + "Configure this requirement with "
                        + "when(returningSelf: ...).thenReturnValue()."
                )
            }
            encodeDynamicSelfResult(
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .optionalSelf {
            guard let outcome = result as? OptionalSelfResultDispatchOutcome else {
                preconditionFailure(
                    "[TestDoubles] Optional dynamic Self handlers must return a supported outcome. "
                        + "Configure this requirement with when(returningOptionalSelf: ...)."
                        + "thenReturnValue(), thenReturnNil(), or then { ... }."
                )
            }
            encodeOptionalDynamicSelfResult(
                outcome,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else {
            encodeReturn(result, for: method, into: frame)
        }
    }

    static func encodeRecordingResult(
        for method: MethodDescriptor,
        args: [Any],
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        if method.kind == .initializer {
            encodeInitializerOutcome(
                .success,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .selfType {
            encodeDynamicSelfResult(
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if method.returnConvention == .optionalSelf {
            encodeOptionalDynamicSelfResult(
                .value,
                for: method,
                recorder: recorder,
                into: frame
            )
        } else if let placeholder = RecordingReturnPlaceholderContext.box {
            encodeReturn(placeholder.value, for: method, into: frame)
        } else {
            encodeRecordingPlaceholder(for: method, args: args, into: frame)
        }
    }

    static func encodeFailure(
        _ error: any Error,
        for method: MethodDescriptor,
        typedErrorDestination: UnsafeMutableRawPointer?,
        into frame: TrampolineCallFrame
    ) {
        guard let typedErrorType = method.typedErrorType,
            let typedErrorLayout = method.typedErrorLayout
        else {
            frame.zeroReturn()
            frame.storeReturnError(swiftErrorPointer(error))
            return
        }
        if method.typedErrorUsesIndirectResultSlot {
            frame.zeroReturn()
            guard let typedErrorDestination else {
                fatalError(
                    "[TestDoubles] Missing typed-error result buffer for \(method.name)."
                )
            }
            copyReturn(
                error,
                expectedType: typedErrorType,
                to: typedErrorDestination
            )
            frame.storeReturnError(1)
            return
        }
        encodeValue(
            error,
            expectedType: typedErrorType,
            abi: typedErrorLayout,
            context: "typed error for \(method.name)",
            isAsync: method.isAsync,
            into: frame
        )
        frame.storeReturnError(1)
    }

    static func copyReturn(
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
        if FunctionReabstraction.initializeDirectReturn(
            value,
            expectedType: expectedType,
            at: destination
        ) == false {
            copyReturn(value, expectedType: expectedType, to: destination)
        }
    }

    static func encodeDynamicFunctionReturn(
        _ value: Any,
        expectedType: Any.Type,
        isAsync: Bool = false,
        into frame: TrampolineCallFrame
    ) {
        encodeValue(
            value,
            expectedType: expectedType,
            abi: abiClass(for: expectedType, isReturn: true),
            context: "dynamic function return",
            isAsync: isAsync,
            into: frame
        )
    }

    static func encodeDynamicFunctionFailure(
        _ error: any Error,
        into frame: TrampolineCallFrame
    ) {
        frame.zeroReturn()
        frame.storeReturnError(swiftErrorPointer(error))
    }

    static func encodeDynamicTypedFunctionFailure(
        _ error: Any,
        expectedType: Any.Type,
        layout: ABIClass,
        destination: UnsafeMutableRawPointer?,
        usesIndirectResultSlot: Bool,
        into frame: TrampolineCallFrame
    ) {
        if usesIndirectResultSlot {
            frame.zeroReturn()
            guard let destination else {
                fatalError(
                    "[TestDoubles] Missing dynamic function typed-error result buffer."
                )
            }
            initializeDirectValue(
                error,
                expectedType: expectedType,
                to: destination
            )
        } else {
            encodeValue(
                error,
                expectedType: expectedType,
                abi: layout,
                context: "dynamic function typed error",
                isAsync: false,
                into: frame
            )
        }
        frame.storeReturnError(1)
    }

    private static func encodeDynamicSelfResult(
        for method: MethodDescriptor,
        recorder: StubRecorder,
        into frame: TrampolineCallFrame
    ) {
        guard let payload = recorder.makeRuntimePayload() else {
            fatalError(
                "[TestDoubles] Dynamic Self runtime resources were released before invocation."
            )
        }
        encodeReturn(payload, for: method, into: frame)
    }

    private static func encodeOptionalDynamicSelfResult(
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
        encodeReturn(payload as Any, for: method, into: frame)
    }

    private static func encodeInitializerOutcome(
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
                encodeReturn(payload, for: method, into: frame)

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
                encodeReturn(payload as Any, for: method, into: frame)

            default:
                preconditionFailure(
                    "[TestDoubles] Initializer \(method.name) does not return dependent Self storage."
                )
        }
    }

    private static func encodeReturn(
        _ result: Any,
        for method: MethodDescriptor,
        into frame: TrampolineCallFrame
    ) {
        encodeValue(
            result,
            expectedType: method.returnType,
            abi: method.returnLayout,
            context: method.name,
            isAsync: method.isAsync,
            into: frame
        )
    }

    private static func encodeValue(
        _ value: Any,
        expectedType: Any.Type,
        abi: ABIClass,
        context: String,
        isAsync: Bool,
        into frame: TrampolineCallFrame
    ) {
        frame.zeroReturn()

        switch abi {
            case .void:
                return

            case .floatingPoint, .integer, .aggregate:
                withCopiedReturn(value, expectedType: expectedType) { source in
                    encodeBorrowedDirectValue(
                        from: source,
                        layout: abi,
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
                    to: destination
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

    private static func encodeRecordingPlaceholder(
        for method: MethodDescriptor,
        args: [Any],
        into frame: TrampolineCallFrame
    ) {
        let abi = method.returnLayout
        frame.zeroReturn()

        switch abi {
            case .void:
                return
            case .floatingPoint:
                return
            case .integer(let words):
                if method.returnType == String.self {
                    encodeReturn("", for: method, into: frame)
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
                    fatalError(
                        "[TestDoubles] Stub cannot synthesize a recording result for \(returnType). "
                            + "Pass a valid value with when(returning:_:) or verify(_:returning:_:) "
                            + "for \(method.name)."
                    )
                }
                initializeAggregatePlaceholder(
                    type: returnType,
                    parts: parts,
                    into: frame
                )
            case .indirect:
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
                    args.indices.contains(index)
                {
                    copyReturn(
                        args[index],
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
                    fatalError(
                        "[TestDoubles] Stub cannot synthesize a recording result for \(returnType). "
                            + "Pass a valid value with when(returning:_:) or verify(_:returning:_:) "
                            + "for \(method.name)."
                    )
                }
        }
    }

    private static func encodeInitializedPlaceholder(
        type: Any.Type,
        for method: MethodDescriptor,
        into frame: TrampolineCallFrame
    ) -> Bool {
        let metadata = reflect(type)
        let storage = metadata.allocateValueBuffer()
        guard PlaceholderValue.initialize(type: type, at: storage) else {
            storage.deallocate()
            return false
        }
        let value = boxValue(type: type, source: storage)
        metadata.vwt.destroy(storage)
        storage.deallocate()
        encodeReturn(value, for: method, into: frame)
        return true
    }

    private static func initializeAggregatePlaceholder(
        type: Any.Type,
        parts: [DirectValuePart],
        into frame: TrampolineCallFrame
    ) {
        let metadata = reflect(type)
        let temporary = metadata.allocateValueBuffer(minimumByteCount: 16)
        guard PlaceholderValue.initialize(type: type, at: temporary) else {
            temporary.deallocate()
            fatalError(
                "[TestDoubles] Stub cannot synthesize a recording placeholder for \(type)."
            )
        }
        encodeAggregateReturn(parts: parts, from: temporary, into: frame)
        // The encoded return registers take ownership of the initialized value.
        temporary.deallocate()
    }

    private static func encodeAggregateReturn(
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

    private static func withCopiedReturn(
        _ result: Any,
        expectedType: Any.Type?,
        _ body: (UnsafeMutableRawPointer) -> Void
    ) {
        let metadata = expectedType.map(reflect) ?? Echo.container(for: result).metadata
        let temporary = metadata.allocateValueBuffer(minimumByteCount: 16)
        temporary.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: metadata.valueBufferByteCount(minimum: 16)
        )
        if let expectedType {
            initializeDirectValue(
                result,
                expectedType: expectedType,
                to: temporary
            )
        } else if expectedType == nil {
            copyReturn(result, expectedType: nil, to: temporary)
        }
        body(temporary)
        // The caller receives the copied value through ABI return storage.
        temporary.deallocate()
    }

    private static func swiftErrorPointer(_ error: any Error) -> UInt {
        var container = Echo.container(for: error)
        let metadata = container.metadata
        guard
            let errorProtocol = (reflect((any Error).self) as? ExistentialMetadata)?
                .protocols.first,
            let witness = swift_conformsToProtocol(
                metadata: metadata,
                protocol: errorProtocol
            )
        else {
            fatalError(
                "[TestDoubles] Cannot find Error witness table for thrown value of type \(metadata.type)."
            )
        }
        let allocated = td_swift_alloc_error(
            metadata.ptr,
            witness.ptr,
            nil,
            false
        )
        metadata.vwt.initializeWithCopy(
            allocated.value,
            UnsafeMutableRawPointer(mutating: container.projectValue())
        )
        return UInt(bitPattern: allocated.error)
    }
}

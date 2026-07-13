#if RUNTIME_STUB
import Echo

private final class RuntimeStubPayload {}

final class RuntimeStubResources: @unchecked Sendable {
    let registryKey: UnsafeRawPointer
    let allocation: UnsafeMutableRawPointer
    var trampolines: [UnsafeRawPointer] = []
    private var isRegistered = false

    init(registryKey: UnsafeRawPointer, allocation: UnsafeMutableRawPointer) {
        self.registryKey = registryKey
        self.allocation = allocation
    }

    func register(_ recorder: StubRecorder) {
        MockRegistry.register(recorder, for: registryKey)
        isRegistered = true
    }

    deinit {
        if isRegistered {
            MockRegistry.remove(for: registryKey)
        }
        for trampoline in trampolines {
            TrampolineFactory.destroy(trampoline)
        }
        allocation.deallocate()
    }
}

private struct PatchedWitnessTable {
    let witnessTable: UnsafeMutableRawPointer
    let resources: RuntimeStubResources
}

extension RuntimeStub {
    static func prepare() throws -> PreparedStub {
        let conformance = try findConformance()
        let signatures = discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )
        let mockableSigs = mockableSignatures(from: signatures)
        let methods = mockableSigs.map { sig in
            MethodDescriptor(
                name: sig.methodName,
                signature: sig.methodSignature,
                index: sig.slot,
                qualifiedArgs: sig.qualifiedArgs,
                qualifiedRet: sig.qualifiedRet,
                isThrowing: sig.isThrowing,
                isAsync: sig.isAsync
            )
        }
        return try prepareThunk(from: conformance, methods: methods)
    }

    static func prepare(slots: [Slot]) throws -> PreparedStub {
        let proto = try extractProtocolDescriptor()
        let mockableIndices = mockableRequirementIndices(for: proto)

        guard slots.count == mockableIndices.count else {
            throw RuntimeStubError.slotCountMismatch(
                protocolName: proto.name,
                expected: mockableIndices.count,
                actual: slots.count
            )
        }

        let methods = zip(slots, mockableIndices).enumerated().map { userIdx, pair in
            MethodDescriptor(
                name: "slot_\(userIdx)",
                signature: pair.0.signature,
                index: pair.1,
                qualifiedArgs: pair.0.qualifiedArgs,
                qualifiedRet: pair.0.qualifiedRet,
                isThrowing: pair.0.isThrowing,
                isAsync: pair.0.isAsync,
                argumentTypes: pair.0.argumentTypes,
                returnType: pair.0.returnType
            )
        }

        return try prepareFabricated(proto: proto, methods: methods)
    }

    static func prepare(methods: [MethodDescriptor]) throws -> PreparedStub {
        try prepareFabricated(proto: extractProtocolDescriptor(), methods: methods)
    }

    static func prepareFromModule(moduleName explicitModuleName: String?) throws -> PreparedStub {
        let proto = try extractProtocolDescriptor()
        let moduleName: String
        if let explicitModuleName {
            moduleName = explicitModuleName
        } else if let inferred = inferredModuleName() {
            moduleName = inferred
        } else {
            throw RuntimeStubError.moduleNameCouldNotBeInferred(typeDescription: String(reflecting: P.self))
        }

        let signatures = try ModuleSignatureDiscovery.discover(
            protocolName: proto.name,
            moduleName: moduleName,
            proto: proto
        )
        let methods = signatures.map { sig in
            MethodDescriptor(
                name: sig.methodName,
                signature: sig.methodSignature,
                index: sig.slot,
                qualifiedArgs: sig.qualifiedArgs,
                qualifiedRet: sig.qualifiedRet,
                isThrowing: sig.isThrowing,
                isAsync: sig.isAsync
            )
        }
        return try prepareFabricated(proto: proto, methods: methods)
    }

    static func extractProtocolDescriptor() throws -> ProtocolDescriptor {
        let meta = reflect(P.self)
        guard let existential = meta as? ExistentialMetadata,
              let protoDesc = existential.protocols.first else {
            throw RuntimeStubError.typeIsNotProtocol(typeDescription: String(reflecting: P.self))
        }
        return protoDesc
    }

    static func inferredModuleName() -> String? {
        var typeDescription = String(reflecting: P.self)
        if typeDescription.hasPrefix("any ") {
            typeDescription.removeFirst(4)
        }
        guard !typeDescription.contains("&") else { return nil }
        let parts = typeDescription.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return String(parts[0])
    }

    static func mockableSignatures(from signatures: [DiscoveredSignature]) -> [DiscoveredSignature] {
        signatures.filter { sig in
            switch sig.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return false
            default:
                return true
            }
        }
    }

    static func failureMessage(for error: Error) -> String {
        if let error = error as? RuntimeStubError {
            return "[TestDoubles] \(error.description)"
        }
        return "[TestDoubles] \(String(describing: error))"
    }

    private static func findConformance() throws -> ConformanceDescriptor {
        let protoDesc = try extractProtocolDescriptor()
        guard let conformance = Echo.findConformance(to: protoDesc) else {
            throw RuntimeStubError.noConformanceFound(
                protocolName: protoDesc.name,
                typeDescription: String(reflecting: P.self)
            )
        }
        return conformance
    }

    private static func prepareThunk(
        from conformance: ConformanceDescriptor,
        methods: [MethodDescriptor]
    ) throws -> PreparedStub {
        let recorder = StubRecorder()
        let patched = try patchWitnessTable(from: conformance, methods: methods, recorder: recorder)
        let containerBytes = try buildExistentialContainer(from: conformance, witnessTable: patched.witnessTable)
        return PreparedStub(
            recorder: recorder,
            resources: patched.resources,
            containerBytes: containerBytes,
            payload: nil
        )
    }

    private static func prepareFabricated(
        proto: ProtocolDescriptor,
        methods: [MethodDescriptor]
    ) throws -> PreparedStub {
        try validate(methods: methods, protocolName: proto.name, requirementCount: proto.numRequirements)

        let recorder = StubRecorder()
        let patched = try fabricateWitnessTable(for: proto, methods: methods, recorder: recorder)
        let payload = RuntimeStubPayload()
        let containerBytes = buildFabricatedExistentialContainer(witnessTable: patched.witnessTable)
        return PreparedStub(
            recorder: recorder,
            resources: patched.resources,
            containerBytes: containerBytes,
            payload: payload
        )
    }

    private static func patchWitnessTable(
        from conformance: ConformanceDescriptor,
        methods: [MethodDescriptor],
        recorder: StubRecorder
    ) throws -> PatchedWitnessTable {
        let proto = conformance.protocol
        try validate(methods: methods, protocolName: proto.name, requirementCount: proto.numRequirements)

        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
        clonedWT.copyMemory(from: conformance.witnessTablePattern.ptr, byteCount: totalWords * wordSize)
        let resources = RuntimeStubResources(
            registryKey: UnsafeRawPointer(clonedWT),
            allocation: clonedWT
        )

        for method in methods {
            guard let thunkPtr = TrampolineFactory.make(
                slot: method.index,
                context: UnsafeRawPointer(clonedWT),
                isAsync: method.isAsync
            ) else {
                throw RuntimeStubError.trampolineAllocationFailed(slot: method.index)
            }
            (clonedWT + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            resources.trampolines.append(thunkPtr)
            recorder.setRuntimeMethod(RuntimeMethodDescriptor(method), for: method.index)
        }

        resources.register(recorder)
        return PatchedWitnessTable(
            witnessTable: clonedWT,
            resources: resources
        )
    }

    private static func fabricateWitnessTable(
        for proto: ProtocolDescriptor,
        methods: [MethodDescriptor],
        recorder: StubRecorder
    ) throws -> PatchedWitnessTable {
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let descriptorSize = 16
        let protocolCellOffset = descriptorSize
        let typeCellOffset = protocolCellOffset + wordSize
        let witnessTableOffset = typeCellOffset + wordSize
        let totalWords = 1 + proto.numRequirements
        let byteCount = witnessTableOffset + totalWords * wordSize

        let allocation = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: wordSize)
        allocation.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        let descriptor = allocation
        let witnessTable = allocation + witnessTableOffset
        let resources = RuntimeStubResources(
            registryKey: UnsafeRawPointer(witnessTable),
            allocation: allocation
        )
        let payloadDescriptor = try payloadContextDescriptor()

        // Heap memory may be more than Int32.max bytes away from image
        // descriptors, so the fabricated conformance uses nearby indirect
        // cells for protocol and type descriptor references.
        descriptor.storeBytes(of: Int32(protocolCellOffset | 1), as: Int32.self)
        (descriptor + 4).storeBytes(of: Int32(typeCellOffset - 4), as: Int32.self)
        (descriptor + 8).storeBytes(of: Int32(witnessTableOffset - 8), as: Int32.self)
        (descriptor + 12).storeBytes(of: UInt32(0x1 << 3), as: UInt32.self)
        (allocation + protocolCellOffset).storeBytes(of: proto.ptr, as: UnsafeRawPointer.self)
        (allocation + typeCellOffset).storeBytes(of: payloadDescriptor, as: UnsafeRawPointer.self)
        witnessTable.storeBytes(of: UnsafeRawPointer(descriptor), as: UnsafeRawPointer.self)

        for method in methods {
            guard let thunkPtr = TrampolineFactory.make(
                slot: method.index,
                context: UnsafeRawPointer(witnessTable),
                isAsync: method.isAsync
            ) else {
                throw RuntimeStubError.trampolineAllocationFailed(slot: method.index)
            }
            (witnessTable + (1 + method.index) * wordSize).storeBytes(of: thunkPtr, as: UnsafeRawPointer.self)
            resources.trampolines.append(thunkPtr)
            recorder.setRuntimeMethod(RuntimeMethodDescriptor(method), for: method.index)
        }

        resources.register(recorder)
        return PatchedWitnessTable(
            witnessTable: witnessTable,
            resources: resources
        )
    }

    private static func buildExistentialContainer(
        from conformance: ConformanceDescriptor,
        witnessTable: UnsafeMutableRawPointer
    ) throws -> ExistentialContainer {
        guard let typeDesc = conformance.contextDescriptor else {
            throw RuntimeStubError.unsupportedTypeKind(typeName: conformance.protocol.name)
        }
        let typeMetaPtr: UnsafeRawPointer
        if let sd = typeDesc as? StructDescriptor {
            typeMetaPtr = unsafeBitCast(sd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let cd = typeDesc as? ClassDescriptor {
            typeMetaPtr = unsafeBitCast(cd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let ed = typeDesc as? EnumDescriptor {
            typeMetaPtr = unsafeBitCast(ed.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else {
            throw RuntimeStubError.unsupportedTypeKind(typeName: typeDesc.name)
        }

        let base = AnyExistentialContainer(type: unsafeBitCast(typeMetaPtr, to: Any.Type.self))
        return ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(witnessTable))
        )
    }

    private static func buildFabricatedExistentialContainer(
        witnessTable: UnsafeMutableRawPointer
    ) -> ExistentialContainer {
        let base = AnyExistentialContainer(type: RuntimeStubPayload.self)
        return ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(witnessTable))
        )
    }

    private static func payloadContextDescriptor() throws -> UnsafeRawPointer {
        guard let metadata = reflect(RuntimeStubPayload.self) as? ClassMetadata else {
            throw RuntimeStubError.unsupportedTypeKind(typeName: String(reflecting: RuntimeStubPayload.self))
        }
        return metadata.descriptor.ptr
    }

    private static func mockableRequirementIndices(for proto: ProtocolDescriptor) -> [Int] {
        proto.requirements.enumerated().compactMap { i, req -> Int? in
            switch req.flags.kind {
            case .modifyCoroutine, .readCoroutine, .baseProtocol,
                 .associatedTypeAccessFunction, .associatedConformanceAccessFunction:
                return nil
            default:
                return i
            }
        }
    }

    private static func validate(
        methods: [MethodDescriptor],
        protocolName: String,
        requirementCount: Int
    ) throws {
        var seen = Set<Int>()
        for method in methods {
            guard method.index >= 0, method.index < requirementCount else {
                throw RuntimeStubError.invalidRequirementIndex(
                    protocolName: protocolName,
                    index: method.index,
                    requirementCount: requirementCount
                )
            }
            guard seen.insert(method.index).inserted else {
                throw RuntimeStubError.duplicateRequirementIndex(
                    protocolName: protocolName,
                    index: method.index
                )
            }
            let concreteTypes = (method.argumentTypes ?? []) + [method.returnType].compactMap { $0 }
            let hasFunctionMetadata = concreteTypes.contains { reflect($0).kind == .function }
            let hasFunctionSpelling = method.argumentTypes == nil && (
                method.qualifiedArgs.contains(where: { $0.contains("->") }) ||
                method.qualifiedRet.contains("->")
            )
            if hasFunctionMetadata || hasFunctionSpelling {
                throw RuntimeStubError.unsupportedFunctionValue(
                    protocolName: protocolName,
                    methodName: method.name
                )
            }
        }
    }
}
#endif // RUNTIME_STUB

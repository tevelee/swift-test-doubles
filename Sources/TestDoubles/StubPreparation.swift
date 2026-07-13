import Echo

private final class StubPayload {}

final class StubResources: @unchecked Sendable {
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
    let resources: StubResources
}

extension Stub {
    static func prepare() throws -> PreparedStub {
        let conformance = try findConformance()
        let signatures = try discoverSignatures(
            witnessTable: conformance.witnessTablePattern,
            proto: conformance.protocol
        )
        let methods = signatures.map { sig in
            MethodDescriptor(
                name: sig.methodName,
                index: sig.slot,
                qualifiedArgs: sig.qualifiedArgs,
                qualifiedRet: sig.qualifiedRet,
                isThrowing: sig.isThrowing,
                isAsync: sig.isAsync
            )
        }
        return try prepareThunk(from: conformance, methods: methods)
    }

    static func prepare(requirements: [Requirement]) throws -> PreparedStub {
        let proto = try extractProtocolDescriptor()
        let protocolRequirements = mockableRequirements(for: proto)

        guard requirements.count == protocolRequirements.count else {
            throw StubError.requirementCountMismatch(
                protocolName: proto.name,
                expected: protocolRequirements.count,
                actual: requirements.count
            )
        }

        var methods: [MethodDescriptor] = []
        methods.reserveCapacity(requirements.count)
        for (requirement, protocolRequirement) in zip(requirements, protocolRequirements) {
            guard requirement.kind == protocolRequirement.kind else {
                throw StubError.requirementKindMismatch(
                    protocolName: proto.name,
                    requirementIndex: protocolRequirement.index,
                    expected: protocolRequirement.kind.rawValue,
                    actual: requirement.kind.rawValue
                )
            }
            methods.append(requirement.descriptor(index: protocolRequirement.index))
        }

        return try prepareFabricated(proto: proto, methods: methods)
    }

    static func extractProtocolDescriptor() throws -> ProtocolDescriptor {
        let meta = reflect(P.self)
        let typeDescription = String(reflecting: P.self)
        guard let existential = meta as? ExistentialMetadata,
              existential.protocols.isEmpty == false else {
            throw StubError.typeIsNotProtocol(typeDescription: typeDescription)
        }
        guard existential.protocols.count == 1 else {
            throw StubError.unsupportedProtocolComposition(typeDescription: typeDescription)
        }
        let proto = existential.protocols[0]
        try validateProtocolShape(existential: existential, descriptor: proto)
        return proto
    }

    private static func findConformance() throws -> ConformanceDescriptor {
        let protoDesc = try extractProtocolDescriptor()
        guard let conformance = Echo.findConformance(to: protoDesc) else {
            throw StubError.noConformanceFound(protocolName: protoDesc.name)
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
        try validate(methods: methods, protocolName: proto.name)

        let recorder = StubRecorder()
        let patched = try fabricateWitnessTable(for: proto, methods: methods, recorder: recorder)
        let payload = StubPayload()
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
        try validate(methods: methods, protocolName: proto.name)

        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let totalWords = 1 + proto.numRequirements
        let clonedWT = UnsafeMutableRawPointer.allocate(byteCount: totalWords * wordSize, alignment: wordSize)
        clonedWT.copyMemory(from: conformance.witnessTablePattern.ptr, byteCount: totalWords * wordSize)
        let resources = StubResources(
            registryKey: UnsafeRawPointer(clonedWT),
            allocation: clonedWT
        )

        try installTrampolines(
            in: clonedWT,
            methods: methods,
            recorder: recorder,
            resources: resources
        )
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
        let resources = StubResources(
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

        try installTrampolines(
            in: witnessTable,
            methods: methods,
            recorder: recorder,
            resources: resources
        )
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
            throw StubError.unsupportedTypeKind(typeName: conformance.protocol.name)
        }
        let typeMetaPtr: UnsafeRawPointer
        if let sd = typeDesc as? StructDescriptor {
            typeMetaPtr = unsafeBitCast(sd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let cd = typeDesc as? ClassDescriptor {
            typeMetaPtr = unsafeBitCast(cd.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else if let ed = typeDesc as? EnumDescriptor {
            typeMetaPtr = unsafeBitCast(ed.accessor(.complete).type, to: UnsafeRawPointer.self)
        } else {
            throw StubError.unsupportedTypeKind(typeName: typeDesc.name)
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
        let base = AnyExistentialContainer(type: StubPayload.self)
        return ExistentialContainer(
            base: base,
            witnessTable: WitnessTable(ptr: UnsafeRawPointer(witnessTable))
        )
    }

    private static func payloadContextDescriptor() throws -> UnsafeRawPointer {
        guard let metadata = reflect(StubPayload.self) as? ClassMetadata else {
            throw StubError.unsupportedTypeKind(typeName: String(reflecting: StubPayload.self))
        }
        return metadata.descriptor.ptr
    }

    private static func installTrampolines(
        in witnessTable: UnsafeMutableRawPointer,
        methods: [MethodDescriptor],
        recorder: StubRecorder,
        resources: StubResources
    ) throws {
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        for method in methods {
            guard let trampoline = TrampolineFactory.make(
                slot: method.index,
                context: UnsafeRawPointer(witnessTable),
                isAsync: method.isAsync
            ) else {
                throw StubError.trampolineAllocationFailed(
                    requirementIndex: method.index
                )
            }
            (witnessTable + (1 + method.index) * wordSize).storeBytes(
                of: trampoline,
                as: UnsafeRawPointer.self
            )
            resources.trampolines.append(trampoline)
            recorder.setRuntimeMethod(RuntimeMethodDescriptor(method), for: method.index)
        }
        resources.register(recorder)
    }

    private static func mockableRequirements(
        for proto: ProtocolDescriptor
    ) -> [(index: Int, kind: StubRequirementKind)] {
        proto.requirements.enumerated().compactMap { index, requirement in
            guard let kind = StubRequirementKind(requirement.flags.kind) else {
                return nil
            }
            return (index, kind)
        }
    }

    private static func validateProtocolShape(
        existential: ExistentialMetadata,
        descriptor proto: ProtocolDescriptor
    ) throws {
        guard existential.flags.isClassConstraint == false,
              existential.flags.hasSuperclassConstraint == false,
              existential.flags.specialProtocol == .none,
              existential.flags.numWitnessTables == 1 else {
            throw StubError.unsupportedProtocolShape(
                protocolName: proto.name,
                reason: "Only ordinary opaque existentials with one witness table are supported."
            )
        }

        for (index, requirement) in proto.requirements.enumerated() {
            guard requirement.flags.isInstance,
                  StubRequirementKind(requirement.flags.kind) != nil else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: proto.name,
                    reason: "Requirement \(index) is a \(requirement.flags.kind). Only instance methods and ordinary getters are supported."
                )
            }
        }
    }

    private static func validate(
        methods: [MethodDescriptor],
        protocolName: String
    ) throws {
        for method in methods {
            let concreteTypes = (method.argumentTypes ?? []) + [method.returnType].compactMap { $0 }
            let hasFunctionMetadata = concreteTypes.contains { reflect($0).kind == .function }
            let hasFunctionSpelling = method.argumentTypes == nil && (
                method.qualifiedArgs.contains(where: { $0.contains("->") }) ||
                method.qualifiedRet.contains("->")
            )
            if hasFunctionMetadata || hasFunctionSpelling {
                throw StubError.unsupportedFunctionValue(
                    protocolName: protocolName,
                    requirementIndex: method.index
                )
            }
        }
    }
}

import Echo

private enum FabricatedWitnessDispatch {
    case stub(
        recorder: StubRecorder,
        methodsByIndex: [Int: MethodDescriptor]
    )
    case dummy(DummyInvocation)

    var invocationTarget: FabricatedInvocationTarget {
        switch self {
            case .stub(let recorder, _):
                return .stub(recorder)
            case .dummy(let invocation):
                return .dummy(invocation)
        }
    }

    func attachRuntimeResources(_ resources: StubResources) {
        guard case .stub(let recorder, _) = self else { return }
        recorder.attachRuntimeResources(resources)
    }

    func makeCallableTrampoline(
        for requirement: ProtocolLayout.CallableRequirement,
        in node: ProtocolLayout.Node,
        witnessTable: UnsafeMutableRawPointer,
        resources: StubResources
    ) throws -> UnsafeRawPointer {
        let trampoline: UnsafeRawPointer?
        switch self {
            case .stub(let recorder, let methodsByIndex):
                guard let method = methodsByIndex[requirement.dispatchIndex] else {
                    throw StubError.requirementCountMismatch(
                        protocolName: node.descriptor.name,
                        expected: node.callableRequirements.count,
                        actual: 0
                    )
                }
                trampoline =
                    if let factory = method.typedWitnessAdapterFactory {
                        resources.makeTypedTrampoline(
                            factory: factory,
                            recorder: recorder,
                            method: method
                        )
                    } else {
                        resources.makeTrampoline(
                            kind: method.isAsync ? .asynchronous : .synchronous,
                            slot: method.index,
                            context: UnsafeRawPointer(witnessTable)
                        )
                    }

            case .dummy:
                let flags = requirement.protocolDescriptor
                    .requirements[requirement.witnessIndex].flags
                trampoline = resources.makeTrampoline(
                    kind: flags.isAsync ? .asynchronous : .synchronous,
                    slot: requirement.dispatchIndex,
                    context: UnsafeRawPointer(witnessTable)
                )
        }

        guard let trampoline else {
            throw StubError.trampolineAllocationFailed(
                requirementIndex: requirement.dispatchIndex
            )
        }
        return trampoline
    }
}

extension Stub {
    static func prepareFabricated(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor]
    ) throws -> PreparedStub {
        let modifyDispatchDescriptors = try validate(
            methods: methods,
            layout: layout,
            representation: representation
        )

        let recorder = StubRecorder(
            methods: methods,
            modifyDispatchDescriptors: modifyDispatchDescriptors
        )
        let protocolName = String(reflecting: P.self)
        let runtimePlan = try FabricatedRuntimePlan.prepare(
            for: representation,
            protocolName: protocolName
        )
        let fabricated = try fabricateWitnessTables(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            dispatch: .stub(
                recorder: recorder,
                methodsByIndex: Dictionary(
                    uniqueKeysWithValues: methods.map { ($0.index, $0) }
                )
            ),
            conformanceTypeReference: runtimePlan.conformanceTypeReference
        )
        return PreparedStub(
            recorder: recorder,
            storage: try FabricatedExistentialStorage(
                witnessTables: fabricated.roots,
                representation: representation,
                payload: runtimePlan.makePayload(resources: fabricated.resources)
            )
        )
    }

    static func prepareDummy() throws -> Dummy<P>.PreparedDummy {
        let shape = try extractProtocolShape()
        let protocolName = String(reflecting: P.self)
        let runtimePlan = try FabricatedRuntimePlan.prepare(
            for: shape.representation,
            protocolName: protocolName
        )
        let invocation = DummyInvocation(
            typeDescription: protocolName,
            requirements: Dictionary(
                uniqueKeysWithValues: shape.layout.callableRequirements.map {
                    requirement in
                    (
                        requirement.dispatchIndex,
                        DummyInvocation.Requirement(
                            protocolName: requirement.protocolDescriptor.name,
                            witnessIndex: requirement.witnessIndex,
                            kind: requirement.kind
                        )
                    )
                }
            )
        )
        let fabricated = try fabricateWitnessTables(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            dispatch: .dummy(invocation),
            conformanceTypeReference: runtimePlan.conformanceTypeReference
        )
        return Dummy<P>.PreparedDummy(
            storage: try FabricatedExistentialStorage(
                witnessTables: fabricated.roots,
                representation: shape.representation,
                payload: runtimePlan.makePayload(resources: fabricated.resources)
            )
        )
    }

    private static func fabricateWitnessTables(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        dispatch: FabricatedWitnessDispatch,
        conformanceTypeReference: FabricatedConformanceTypeReference
    ) throws -> FabricatedWitnessTables {
        let resources = StubResources()
        dispatch.attachRuntimeResources(resources)
        let witnessTables = try fabricateWitnessTableGraph(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            conformanceTypeReference: conformanceTypeReference,
            resources: resources
        )

        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        for node in layout.nodes {
            let identifier = ProtocolLayout.DescriptorID(node.descriptor)
            guard let witnessTable = witnessTables[identifier] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Failed to allocate a protocol witness table."
                )
            }
            for requirement in node.callableRequirements {
                let trampoline = try dispatch.makeCallableTrampoline(
                    for: requirement,
                    in: node,
                    witnessTable: witnessTable,
                    resources: resources
                )
                (witnessTable + (1 + requirement.witnessIndex) * wordSize).storeBytes(
                    of: trampoline,
                    as: UnsafeRawPointer.self
                )
            }

            for requirement in node.modifyCoroutineRequirements {
                guard
                    let trampoline = resources.makeTrampoline(
                        kind: .modify,
                        slot: requirement.getterDispatchIndex,
                        context: UnsafeRawPointer(witnessTable)
                    )
                else {
                    throw StubError.trampolineAllocationFailed(
                        requirementIndex: requirement.witnessIndex
                    )
                }
                (witnessTable + (1 + requirement.witnessIndex) * wordSize).storeBytes(
                    of: trampoline,
                    as: UnsafeRawPointer.self
                )
            }
        }

        try resources.publishTrampolines()
        for witnessTable in witnessTables.values {
            resources.register(dispatch.invocationTarget, for: UnsafeRawPointer(witnessTable))
        }
        return try fabricatedWitnessTables(
            layout: layout,
            witnessTables: witnessTables,
            resources: resources
        )
    }

    private static func fabricateWitnessTableGraph(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        conformanceTypeReference: FabricatedConformanceTypeReference,
        resources: StubResources
    ) throws -> [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer] {
        var witnessTables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer] = [:]
        for node in layout.nodes {
            witnessTables[ProtocolLayout.DescriptorID(node.descriptor)] =
                allocateWitnessTable(
                    for: node.descriptor,
                    conformanceTypeReference: conformanceTypeReference,
                    resources: resources
                )
        }

        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        for node in layout.nodes {
            let identifier = ProtocolLayout.DescriptorID(node.descriptor)
            guard let witnessTable = witnessTables[identifier] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Failed to allocate a protocol witness table."
                )
            }
            for baseProtocol in node.baseProtocols {
                guard
                    let baseWitnessTable = witnessTables[
                        ProtocolLayout.DescriptorID(baseProtocol.descriptor)
                    ]
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: node.descriptor.name,
                        reason: "A fabricated base-protocol witness table is missing."
                    )
                }
                (witnessTable + (1 + baseProtocol.witnessIndex) * wordSize).storeBytes(
                    of: UnsafeRawPointer(baseWitnessTable),
                    as: UnsafeRawPointer.self
                )
            }

            for requirement in node.associatedTypes {
                let binding = try associatedTypeBindings.binding(
                    named: requirement.name,
                    declaredBy: requirement.protocolDescriptor
                )
                let metadata = unsafeBitCast(binding.type, to: UnsafeRawPointer.self)
                (witnessTable + (1 + requirement.witnessIndex) * wordSize).storeBytes(
                    of: metadata,
                    as: UnsafeRawPointer.self
                )
            }

            for requirement in node.associatedConformances {
                let binding = try associatedTypeBindings.binding(
                    named: requirement.associatedTypeName,
                    declaredBy: requirement.protocolDescriptor
                )
                let metadata = unsafeBitCast(binding.type, to: UnsafeRawPointer.self)
                guard
                    let conformance = runtimeConformance(
                        metadata,
                        requirement.constraint.ptr
                    )
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: node.descriptor.name,
                        reason: "Bound associated type '\(runtimeTypeName(binding.type))' does not conform to '\(requirement.constraint.name)'."
                    )
                }
                (witnessTable + (1 + requirement.witnessIndex) * wordSize).storeBytes(
                    of: conformance,
                    as: UnsafeRawPointer.self
                )
            }
        }
        return witnessTables
    }

    private static func fabricatedWitnessTables(
        layout: ProtocolLayout,
        witnessTables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer],
        resources: StubResources
    ) throws -> FabricatedWitnessTables {
        let roots = try layout.roots.map { root -> UnsafeMutableRawPointer in
            guard let witnessTable = witnessTables[ProtocolLayout.DescriptorID(root)] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: root.name,
                    reason: "Failed to fabricate the root witness table."
                )
            }
            return witnessTable
        }
        return FabricatedWitnessTables(roots: roots, resources: resources)
    }

    private static func allocateWitnessTable(
        for proto: ProtocolDescriptor,
        conformanceTypeReference: FabricatedConformanceTypeReference,
        resources: StubResources
    ) -> UnsafeMutableRawPointer {
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let descriptorSize = 16
        let protocolCellOffset = descriptorSize
        let typeReferenceOffset = protocolCellOffset + wordSize
        let typeReferenceSize: Int
        switch conformanceTypeReference {
            case .indirectTypeDescriptor:
                typeReferenceSize = wordSize
            case .directObjectiveCClassName(let bytes):
                typeReferenceSize = bytes.count
        }
        let unalignedWitnessTableOffset = typeReferenceOffset + typeReferenceSize
        let witnessTableOffset =
            (unalignedWitnessTableOffset + wordSize - 1) & ~(wordSize - 1)
        let totalWords = 1 + proto.numRequirements
        let byteCount = witnessTableOffset + totalWords * wordSize

        let allocation = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: wordSize
        )
        allocation.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        resources.own(allocation)

        let descriptor = allocation
        let witnessTable = allocation + witnessTableOffset

        // Heap memory may be more than Int32.max bytes away from image
        // descriptors, so the fabricated conformance uses nearby indirect
        // cells for protocol and Swift type-descriptor references. Imported
        // Objective-C classes use the ABI's direct class-name reference.
        descriptor.storeBytes(of: Int32(protocolCellOffset | 1), as: Int32.self)
        (descriptor + 4).storeBytes(of: Int32(typeReferenceOffset - 4), as: Int32.self)
        (descriptor + 8).storeBytes(of: Int32(witnessTableOffset - 8), as: Int32.self)
        (allocation + protocolCellOffset).storeBytes(of: proto.ptr, as: UnsafeRawPointer.self)
        switch conformanceTypeReference {
            case .indirectTypeDescriptor(let descriptorPointer):
                (descriptor + 12).storeBytes(of: UInt32(0x1 << 3), as: UInt32.self)
                (allocation + typeReferenceOffset).storeBytes(
                    of: descriptorPointer,
                    as: UnsafeRawPointer.self
                )
            case .directObjectiveCClassName(let bytes):
                (descriptor + 12).storeBytes(of: UInt32(0x2 << 3), as: UInt32.self)
                for (index, byte) in bytes.enumerated() {
                    (allocation + typeReferenceOffset + index).storeBytes(
                        of: byte,
                        as: UInt8.self
                    )
                }
        }
        witnessTable.storeBytes(of: UnsafeRawPointer(descriptor), as: UnsafeRawPointer.self)
        return witnessTable
    }
}

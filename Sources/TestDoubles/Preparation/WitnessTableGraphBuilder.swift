import Echo

struct FabricatedWitnessTableGraph {
    let tables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer]

    func rootTables(
        for layout: ProtocolLayout
    ) throws -> [UnsafeMutableRawPointer] {
        try layout.roots.map { root in
            guard let witnessTable = tables[ProtocolLayout.DescriptorID(root)] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: root.name,
                    reason: "Failed to fabricate the root witness table."
                )
            }
            return witnessTable
        }
    }
}

struct WitnessTableGraphBuilder {
    let layout: ProtocolLayout
    let associatedTypeBindings: AssociatedTypeBindings
    let conformanceTypeReference: FabricatedConformanceTypeReference
    let resources: StubResources

    func build() throws -> FabricatedWitnessTableGraph {
        var witnessTables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer] = [:]
        for node in layout.nodes {
            witnessTables[ProtocolLayout.DescriptorID(node.descriptor)] =
                allocateWitnessTable(for: node.descriptor)
        }

        try populateGraphReferences(in: witnessTables)
        return FabricatedWitnessTableGraph(tables: witnessTables)
    }

    private func populateGraphReferences(
        in witnessTables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer]
    ) throws {
        for node in layout.nodes {
            let identifier = ProtocolLayout.DescriptorID(node.descriptor)
            guard let witnessTable = witnessTables[identifier] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Failed to allocate a protocol witness table."
                )
            }
            try populateBaseProtocols(
                of: node,
                in: witnessTable,
                from: witnessTables
            )
            try populateAssociatedTypes(of: node, in: witnessTable)
            try populateAssociatedConformances(of: node, in: witnessTable)
        }
    }

    private func populateBaseProtocols(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer,
        from witnessTables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer]
    ) throws {
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
            witnessEntry(
                at: baseProtocol.witnessIndex,
                in: witnessTable
            ).storeBytes(
                of: UnsafeRawPointer(baseWitnessTable),
                as: UnsafeRawPointer.self
            )
        }
    }

    private func populateAssociatedTypes(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer
    ) throws {
        for requirement in node.associatedTypes {
            let binding = try associatedTypeBindings.binding(
                named: requirement.name,
                declaredBy: requirement.protocolDescriptor
            )
            let metadata = unsafeBitCast(binding.type, to: UnsafeRawPointer.self)
            witnessEntry(
                at: requirement.witnessIndex,
                in: witnessTable
            ).storeBytes(
                of: metadata,
                as: UnsafeRawPointer.self
            )
        }
    }

    private func populateAssociatedConformances(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer
    ) throws {
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
            witnessEntry(
                at: requirement.witnessIndex,
                in: witnessTable
            ).storeBytes(
                of: conformance,
                as: UnsafeRawPointer.self
            )
        }
    }

    private func allocateWitnessTable(
        for proto: ProtocolDescriptor
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
        (allocation + protocolCellOffset).storeBytes(
            of: proto.ptr,
            as: UnsafeRawPointer.self
        )
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
        witnessTable.storeBytes(
            of: UnsafeRawPointer(descriptor),
            as: UnsafeRawPointer.self
        )
        return witnessTable
    }

    private func witnessEntry(
        at index: Int,
        in witnessTable: UnsafeMutableRawPointer
    ) -> UnsafeMutableRawPointer {
        witnessTable + (1 + index) * MemoryLayout<UnsafeRawPointer>.size
    }
}

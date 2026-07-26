import CTestDoublesTrampoline
import Echo
import TestDoublesRuntimeMetadata

package struct FabricatedWitnessTableGraph {
    let tables: [ProtocolLayout.DescriptorID: UnsafeMutableRawPointer]

    package func rootTables(
        for layout: ProtocolLayout
    ) throws -> [UnsafeMutableRawPointer] {
        try layout.roots.map { root in
            guard let witnessTable = tables[ProtocolLayout.DescriptorID(root)] else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: root.name,
                    reason: "Failed to fabricate the root witness table."
                )
            }
            return witnessTable
        }
    }
}

/// `ConformanceFlags::TypeReferenceKind` values (include/swift/ABI/
/// MetadataValues.h), shifted into their field position by
/// `TypeMetadataKindShift = 3` in the conformance descriptor's `Flags` word.
private enum TypeReferenceKindFlag {
    static let indirectTypeDescriptor: UInt32 = 0x1 << 3
    static let directObjCClassName: UInt32 = 0x2 << 3
}

private func runtimeConformance(
    _ type: UnsafeRawPointer,
    _ protocolDescriptor: UnsafeRawPointer
) -> UnsafeRawPointer? {
    typealias Function =
        @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?
    guard let function: Function = RuntimeSymbols.function(named: "swift_conformsToProtocol")
    else { return nil }
    return function(type, protocolDescriptor)
}

package struct WitnessTableGraphBuilder {
    let layout: ProtocolLayout
    let associatedTypeBindings: AssociatedTypeBindings
    let conformanceTypeReference: FabricatedConformanceTypeReference
    let resources: FabricatedRuntimeResources

    package func build() throws -> FabricatedWitnessTableGraph {
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
                throw RuntimeConstructionError.unsupportedProtocolShape(
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
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "A fabricated base-protocol witness table is missing."
                )
            }
            ProtocolWitnessTableLayout.entry(
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
            ProtocolWitnessTableLayout.entry(
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
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Bound associated type '\(runtimeTypeName(binding.type))' does not conform to '\(requirement.constraint.name)'."
                )
            }
            ProtocolWitnessTableLayout.entry(
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
                (descriptor + 12).storeBytes(
                    of: TypeReferenceKindFlag.indirectTypeDescriptor,
                    as: UInt32.self
                )
                let cell = allocation + typeReferenceOffset
                let signedDescriptorPointer =
                    td_sign_type_descriptor_pointer(descriptorPointer, cell)
                    ?? descriptorPointer
                cell.storeBytes(
                    of: signedDescriptorPointer,
                    as: UnsafeRawPointer.self
                )
            case .directObjectiveCClassName(let bytes):
                (descriptor + 12).storeBytes(
                    of: TypeReferenceKindFlag.directObjCClassName,
                    as: UInt32.self
                )
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
}

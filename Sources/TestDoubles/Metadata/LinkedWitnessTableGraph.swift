import Echo

/// Resolves the witness tables linked through a protocol existential or an
/// image conformance into the descriptor-keyed graph consumed by discovery.
enum LinkedWitnessTableGraph {
    static func discover(
        in layout: ProtocolLayout
    ) throws -> [ProtocolLayout.DescriptorID: WitnessTable] {
        var witnessTables: [ProtocolLayout.DescriptorID: WitnessTable] = [:]
        for root in layout.roots {
            guard let conformance = Echo.findConformance(to: root) else { continue }
            try collect(
                descriptor: root,
                witnessTable: conformance.witnessTablePattern,
                layout: layout,
                into: &witnessTables
            )
        }
        return witnessTables
    }

    static func collect(
        descriptor: ProtocolDescriptor,
        witnessTable: WitnessTable,
        layout: ProtocolLayout,
        into witnessTables: inout [ProtocolLayout.DescriptorID: WitnessTable]
    ) throws {
        let identifier = ProtocolLayout.DescriptorID(descriptor)
        if witnessTables[identifier] != nil { return }
        guard let node = layout.node(for: descriptor) else {
            throw StubError.unsupportedProtocolShape(
                protocolName: descriptor.name,
                reason: "Inherited-protocol metadata changed while resolving linked witnesses."
            )
        }
        witnessTables[identifier] = witnessTable
        for baseProtocol in node.baseProtocols {
            let pointer = ProtocolWitnessTableLayout.entry(
                at: baseProtocol.witnessIndex,
                in: witnessTable.ptr
            ).load(as: UnsafeRawPointer?.self)
            guard let pointer else {
                throw StubError.signatureDiscoveryFailed(
                    protocolName: descriptor.name,
                    requirementIndex: baseProtocol.witnessIndex,
                    details: "The linked base-protocol witness table is null. Supply explicit Requirement values."
                )
            }
            try collect(
                descriptor: baseProtocol.descriptor,
                witnessTable: WitnessTable(ptr: pointer),
                layout: layout,
                into: &witnessTables
            )
        }
    }
}

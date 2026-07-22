import CTestDoublesTrampoline

struct WitnessEntryInstaller {
    let layout: ProtocolLayout
    let dispatch: FabricatedWitnessDispatch
    let resources: StubResources

    func install(in graph: FabricatedWitnessTableGraph) throws {
        for node in layout.nodes {
            let identifier = ProtocolLayout.DescriptorID(node.descriptor)
            guard let witnessTable = graph.tables[identifier] else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Failed to allocate a protocol witness table."
                )
            }
            try installCallableEntries(of: node, in: witnessTable)
            try installReadEntries(of: node, in: witnessTable)
            try installModifyEntries(of: node, in: witnessTable)
        }
    }

    private func installCallableEntries(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer
    ) throws {
        let readWitnessIndices = Set(
            node.readCoroutineRequirements.map(\.witnessIndex)
        )
        for requirement in node.callableRequirements
        where readWitnessIndices.contains(requirement.witnessIndex) == false {
            let trampoline = try dispatch.makeCallableTrampoline(
                for: requirement,
                in: node,
                witnessTable: witnessTable,
                resources: resources
            )
            ProtocolWitnessTableLayout.entry(
                at: requirement.witnessIndex,
                in: witnessTable
            ).storeBytes(
                of: trampoline,
                as: UnsafeRawPointer.self
            )
        }
    }

    private func installReadEntries(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer
    ) throws {
        // Swift 6.4 retains a legacy yield_once slot before each supported
        // yielding-borrow slot. The table is zero-initialized, so leave that
        // unsupported compatibility slot unavailable instead of installing a
        // yield_once_2 descriptor with the wrong ABI.
        for requirement in node.readCoroutineRequirements
        where requirement.abi == .yieldOnce2 {
            let plan = try dispatch.readPlan(
                for: requirement,
                in: node
            )
            guard
                let descriptor = resources.makeTrampoline(
                    kind: .read(
                        resumeDiscriminator: plan.resumeDiscriminator
                    ),
                    slot: requirement.recorderDispatchIndex,
                    context: UnsafeRawPointer(witnessTable)
                )
            else {
                throw StubError.trampolineAllocationFailed(
                    requirementIndex: requirement.witnessIndex
                )
            }
            let slot = ProtocolWitnessTableLayout.entry(
                at: requirement.witnessIndex,
                in: witnessTable
            )
            let signedDescriptor =
                td_sign_coro_witness_pointer(
                    descriptor,
                    UnsafeRawPointer(slot),
                    declarationDiscriminator(
                        for: requirement.witnessIndex,
                        in: node
                    )
                ) ?? descriptor
            slot.storeBytes(
                of: signedDescriptor,
                as: UnsafeRawPointer.self
            )
        }
    }

    private func installModifyEntries(
        of node: ProtocolLayout.Node,
        in witnessTable: UnsafeMutableRawPointer
    ) throws {
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
            let slot = ProtocolWitnessTableLayout.entry(
                at: requirement.witnessIndex,
                in: witnessTable
            )
            let signedTrampoline =
                td_sign_modify_witness_pointer(
                    trampoline,
                    UnsafeRawPointer(slot),
                    declarationDiscriminator(
                        for: requirement.witnessIndex,
                        in: node
                    )
                ) ?? trampoline
            slot.storeBytes(
                of: signedTrampoline,
                as: UnsafeRawPointer.self
            )
        }
    }

    private func declarationDiscriminator(
        for witnessIndex: Int,
        in node: ProtocolLayout.Node
    ) -> UInt16 {
        UInt16(
            truncatingIfNeeded: node.descriptor
                .requirements[witnessIndex].flags.bits >> 16
        )
    }
}

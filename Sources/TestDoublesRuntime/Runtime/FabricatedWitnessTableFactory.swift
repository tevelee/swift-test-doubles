import TestDoublesRuntimeMetadata
/// Builds one complete fabricated conformance graph and publishes its callable
/// trampolines. The public target supplies only validated metadata and an
/// opaque semantic endpoint.
package enum FabricatedWitnessTableFactory {
    package static func fabricate(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        invocation: RuntimeFabricatedInvocation,
        conformanceTypeReference: FabricatedConformanceTypeReference
    ) throws -> FabricatedWitnessTables {
        let resources = FabricatedRuntimeResources()
        let graph = try WitnessTableGraphBuilder(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            conformanceTypeReference: conformanceTypeReference,
            resources: resources
        ).build()
        try WitnessEntryInstaller(
            layout: layout,
            dispatch: FabricatedWitnessDispatch(invocation: invocation),
            resources: resources
        ).install(in: graph)

        try resources.publishTrampolines()
        for witnessTable in graph.tables.values {
            resources.register(invocation, for: UnsafeRawPointer(witnessTable))
        }
        return FabricatedWitnessTables(
            roots: try graph.rootTables(for: layout),
            resources: resources
        )
    }
}

import InternalRuntimeContract
import TestDoublesRuntimeMetadata

/// Builds an opaque fabricated existential from validated semantic inputs.
///
/// The factory owns the complete ABI construction transaction. Callers supply
/// only metadata already validated by their policy layer and an opaque
/// semantic endpoint; witness tables, resource owners, payloads, and
/// conformance references never leave this boundary.
package enum RuntimeStubFactory {
    /// A materializable existential value whose ABI storage remains private to
    /// the runtime target.
    package struct Storage<P> {
        private let storage: FabricatedExistentialStorage<P>

        fileprivate init(storage: FabricatedExistentialStorage<P>) {
            self.storage = storage
        }

        package func materialize() -> P {
            storage.materialize()
        }
    }

    /// Fabricates one complete conformance graph and materializable
    /// existential value.
    ///
    /// The semantic endpoint receives the resource owner only after witness
    /// publication, while construction can still fail without committing the
    /// witness identities to runtime metadata caches.
    package static func fabricate<P>(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        endpoint: any RuntimeInvocationEndpoint,
        protocolName: String,
        forwarder: (any RuntimeForwarding)? = nil
    ) throws -> Storage<P> {
        let runtimePlan = try FabricatedRuntimePlan.prepare(
            for: representation,
            protocolName: protocolName
        )
        let invocation = RuntimeFabricatedInvocation(
            endpoint: endpoint,
            methodsByIndex: Dictionary(
                uniqueKeysWithValues: methods.map { ($0.index, $0) }
            ),
            forwarder: forwarder
        )
        let fabricated = try FabricatedWitnessTableFactory.fabricate(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            invocation: invocation,
            conformanceTypeReference: runtimePlan.conformanceTypeReference
        )
        endpoint.runtimeResourcesDidPublish(fabricated.resources)
        let storage: FabricatedExistentialStorage<P> = try fabricated.makeStorage(
            representation: representation,
            payload: runtimePlan.makePayload(resources: fabricated.resources)
        )
        return Storage(storage: storage)
    }
}

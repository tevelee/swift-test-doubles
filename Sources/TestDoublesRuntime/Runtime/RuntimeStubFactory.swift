import InternalRuntimeContract

/// Builds an opaque fabricated existential from validated semantic inputs.
/// Owns the complete ABI construction transaction: witness tables, resource
/// owners, payloads, and conformance references never leave this boundary.
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

    /// A validated construction plan with semantic recorder information and
    /// private runtime storage. The public layer can build its recorder from
    /// the projected methods, but cannot inspect descriptors or ABI layouts.
    package struct PreparedPlan<P> {
        package let methods: [RuntimeMethod]
        package let modifyDispatches: [Int: RuntimeModifyDispatch]
        package let allowsForwardingFallback: Bool

        private let layout: ProtocolLayout
        private let associatedTypeBindings: AssociatedTypeBindings
        private let representation: StubExistentialRepresentation
        private let preparedMethods: [PreparedRuntimeMethod]
        private let forwarder: (any RuntimeForwarding)?

        package init(
            layout: ProtocolLayout,
            associatedTypeBindings: AssociatedTypeBindings,
            representation: StubExistentialRepresentation,
            descriptors: [MethodDescriptor],
            forwarder: (any RuntimeForwarding)?,
            modifyDispatches: [Int: RuntimeModifyDispatch]
        ) {
            self.layout = layout
            self.associatedTypeBindings = associatedTypeBindings
            self.representation = representation
            preparedMethods = descriptors.map(PreparedRuntimeMethod.init)
            self.forwarder = forwarder
            self.modifyDispatches = modifyDispatches
            methods = descriptors.map(\.runtimeMethod)
            allowsForwardingFallback = forwarder != nil
        }

        package func materialize(
            endpoint: any RuntimeInvocationEndpoint,
            protocolName: String
        ) throws -> Storage<P> {
            try RuntimeStubFactory.fabricate(
                layout: layout,
                associatedTypeBindings: associatedTypeBindings,
                representation: representation,
                preparedMethods: preparedMethods,
                endpoint: endpoint,
                protocolName: protocolName,
                forwarder: forwarder
            )
        }
    }

    /// A materializable dummy plan that exposes only failure diagnostics.
    package struct PreparedDummyPlan<P> {
        package let requirements: [RuntimeDummyRequirement]
        private let layout: ProtocolLayout
        private let associatedTypeBindings: AssociatedTypeBindings
        private let representation: StubExistentialRepresentation

        package init(
            layout: ProtocolLayout,
            associatedTypeBindings: AssociatedTypeBindings,
            representation: StubExistentialRepresentation,
            requirements: [RuntimeDummyRequirement]
        ) {
            self.layout = layout
            self.associatedTypeBindings = associatedTypeBindings
            self.representation = representation
            self.requirements = requirements
        }

        package func materialize(
            endpoint: any RuntimeInvocationEndpoint,
            protocolName: String
        ) throws -> Storage<P> {
            try RuntimeStubFactory.fabricate(
                layout: layout,
                associatedTypeBindings: associatedTypeBindings,
                representation: representation,
                preparedMethods: [],
                endpoint: endpoint,
                protocolName: protocolName
            )
        }
    }

    /// Creates an opaque payload owner for values that must retain runtime
    /// resources while a semantic recorder holds the generated value.
    package static func makePayload(resources: AnyObject) -> AnyObject {
        FabricatedPayload(resources: resources)
    }

    /// Synthesizes a source-level placeholder without exposing its runtime
    /// implementation type to the semantic target.
    package static func makeRecordingPlaceholder<T>(for type: T.Type) -> T? {
        PlaceholderValue.make(type)
    }

    /// Synthesizes a valid concrete dummy, including fail-closed function values.
    package static func makeDummyValue<T>(for type: T.Type) -> T? {
        DummyValue.make(type)
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
        preparedMethods: [PreparedRuntimeMethod],
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
            preparedMethods: preparedMethods,
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

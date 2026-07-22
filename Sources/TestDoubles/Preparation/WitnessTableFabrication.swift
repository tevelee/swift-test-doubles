extension Stub {
    static func prepareFabricated(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        forwarder: (any ProtocolForwarding)? = nil
    ) throws -> PreparedStub {
        let modifyDispatchDescriptors = try validate(
            methods: methods,
            layout: layout,
            representation: representation
        )

        let recorder = StubRecorder(
            methods: methods,
            modifyDispatchDescriptors: modifyDispatchDescriptors,
            allowsForwardingFallback: forwarder != nil
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
                ),
                forwarder: forwarder
            ),
            conformanceTypeReference: runtimePlan.conformanceTypeReference
        )
        let storage: FabricatedExistentialStorage<P> = try fabricated.makeStorage(
            representation: representation,
            payload: runtimePlan.makePayload(resources: fabricated.resources)
        )
        return PreparedStub(
            recorder: recorder,
            storage: storage
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
        let storage: FabricatedExistentialStorage<P> = try fabricated.makeStorage(
            representation: shape.representation,
            payload: runtimePlan.makePayload(resources: fabricated.resources)
        )
        return Dummy<P>.PreparedDummy(
            storage: storage
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

        let graph = try WitnessTableGraphBuilder(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            conformanceTypeReference: conformanceTypeReference,
            resources: resources
        ).build()
        try WitnessEntryInstaller(
            layout: layout,
            dispatch: dispatch,
            resources: resources
        ).install(in: graph)

        try resources.publishTrampolines()
        for witnessTable in graph.tables.values {
            resources.register(
                dispatch.invocationTarget,
                for: UnsafeRawPointer(witnessTable)
            )
        }
        return FabricatedWitnessTables(
            roots: try graph.rootTables(for: layout),
            resources: resources
        )
    }
}

import TestDoublesRuntime

extension Stub {
    static func prepareFabricated(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        forwarder: (any RuntimeForwarding)? = nil
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
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)
        let protocolName = String(reflecting: P.self)
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
        recorder.attachRuntimeResources(fabricated.resources)
        let storage: FabricatedExistentialStorage<P> = try fabricated.makeStorage(
            representation: representation,
            payload: runtimePlan.makePayload(resources: fabricated.resources)
        )
        return PreparedStub(recorder: recorder, storage: storage)
    }

    static func prepareDummy() throws -> Dummy<P>.PreparedDummy {
        let shape = try extractProtocolShape()
        let protocolName = String(reflecting: P.self)
        let runtimePlan = try FabricatedRuntimePlan.prepare(
            for: shape.representation,
            protocolName: protocolName
        )
        let endpoint = DummyInvocationEndpoint(
            typeDescription: protocolName,
            requirements: Dictionary(
                uniqueKeysWithValues: shape.layout.callableRequirements.map {
                    requirement in
                    (
                        requirement.dispatchIndex,
                        DummyInvocationEndpoint.Requirement(
                            protocolName: requirement.protocolDescriptor.name,
                            witnessIndex: requirement.witnessIndex,
                            kind: requirement.kind
                        )
                    )
                }
            )
        )
        let fabricated = try FabricatedWitnessTableFactory.fabricate(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            invocation: RuntimeFabricatedInvocation(
                endpoint: endpoint,
                methodsByIndex: [:]
            ),
            conformanceTypeReference: runtimePlan.conformanceTypeReference
        )
        let storage: FabricatedExistentialStorage<P> = try fabricated.makeStorage(
            representation: shape.representation,
            payload: runtimePlan.makePayload(resources: fabricated.resources)
        )
        return Dummy<P>.PreparedDummy(storage: storage)
    }
}

final class DummyInvocationEndpoint: RuntimeInvocationEndpoint,
    @unchecked Sendable
{
    struct Requirement: Sendable {
        let protocolName: String
        let witnessIndex: Int
        let kind: StubRequirementKind
    }

    private let typeDescription: String
    private let requirements: [Int: Requirement]

    init(
        typeDescription: String,
        requirements: [Int: Requirement]
    ) {
        self.typeDescription = typeDescription
        self.requirements = requirements
    }

    var invocationMode: RuntimeInvocationMode { .normal }

    func prepareDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimePreparedDispatch {
        _ = method
        _ = args
        rejectInvocation(at: method.index)
    }

    func prepareAsyncDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeAsyncDispatch {
        _ = args
        rejectInvocation(at: method.index)
    }

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)? {
        _ = getterIndex
        return nil
    }

    func rejectInvocation(at slot: Int) -> Never {
        fatalError(rejectionMessage(slot: slot))
    }

    func recordingAccessorResult(for method: MethodDescriptor) -> Any {
        rejectInvocation(at: method.index)
    }

    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as resultType: Result.Type
    ) throws -> Result {
        _ = args
        _ = resultType
        rejectInvocation(at: method.index)
    }

    func runtimePayload() -> AnyObject? { nil }

    func dependentResult(
        for result: Any,
        method: MethodDescriptor
    ) -> RuntimeDependentResult {
        _ = result
        rejectInvocation(at: method.index)
    }

    func recordingResult(
        for method: MethodDescriptor,
        args: [Any]
    ) -> RuntimeRecordingResult {
        _ = args
        rejectInvocation(at: method.index)
    }

    func rejectionMessage(slot: Int) -> String {
        let requirementDescription =
            requirements[slot].map {
                "\($0.protocolName) \($0.kind.rawValue) requirement at witness index \($0.witnessIndex)"
            } ?? "unknown requirement at dispatch slot \(slot)"
        return "[TestDoubles] Dummy<\(typeDescription)> was invoked through \(requirementDescription). "
            + "A dummy may only be passed to code paths that do not use it. If this invocation is "
            + "expected, replace the dummy with `Stub`, `ManualStub`, or a hand-written fake."
    }
}

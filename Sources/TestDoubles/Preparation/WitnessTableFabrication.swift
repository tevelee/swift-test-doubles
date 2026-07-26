import InternalRuntimeContract
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

        let fabricatedMethodCatalog = FabricatedMethodCatalog(
            methods: methods,
            modifyDispatchDescriptors: modifyDispatchDescriptors
        )
        let recorder = StubRecorder(
            methods: [],
            fabricatedMethodCatalog: fabricatedMethodCatalog,
            allowsForwardingFallback: forwarder != nil
        )
        let endpoint = StubRecorderInvocationEndpoint(
            recorder: recorder,
            fabricatedMethodCatalog: fabricatedMethodCatalog
        )
        let protocolName = String(reflecting: P.self)
        let storage: RuntimeStubFactory.Storage<P> = try RuntimeStubFactory.fabricate(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            representation: representation,
            methods: methods,
            endpoint: endpoint,
            protocolName: protocolName,
            forwarder: forwarder
        )
        return PreparedStub(recorder: recorder, storage: storage)
    }

    static func prepareDummy() throws -> Dummy<P>.PreparedDummy {
        let shape = try extractProtocolShape()
        let protocolName = String(reflecting: P.self)
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
        let storage: RuntimeStubFactory.Storage<P> = try RuntimeStubFactory.fabricate(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            methods: [],
            endpoint: endpoint,
            protocolName: protocolName
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
        _ request: RuntimeInvocationRequest
    ) -> RuntimePreparedDispatch {
        _ = request.arguments
        rejectInvocation(at: request.slot)
    }

    func prepareAsyncDispatch(
        _ request: RuntimeInvocationRequest
    ) -> RuntimeAsyncDispatch {
        _ = request.arguments
        rejectInvocation(at: request.slot)
    }

    func modifyDispatch(
        forGetterSlot getterSlot: Int
    ) -> RuntimeModifyDispatch? {
        _ = getterSlot
        return nil
    }

    func rejectInvocation(at slot: Int) -> Never {
        fatalError(rejectionMessage(slot: slot))
    }

    func methodName(at slot: Int) -> String {
        requirements[slot].map {
            "\($0.protocolName) \($0.kind.rawValue) requirement"
        } ?? "unknown requirement at dispatch slot \(slot)"
    }

    func recordingAccessorResult(at slot: Int) -> Any {
        rejectInvocation(at: slot)
    }

    func dispatchTyped<Result>(
        _ request: RuntimeInvocationRequest,
        as resultType: Result.Type
    ) throws -> Result {
        _ = request.arguments
        _ = resultType
        rejectInvocation(at: request.slot)
    }

    func runtimeResourcesDidPublish(_ resources: AnyObject) {
        _ = resources
    }

    func runtimePayload() -> AnyObject? { nil }

    func dependentResult(
        for result: Any,
        at slot: Int
    ) -> RuntimeDependentResult {
        _ = result
        rejectInvocation(at: slot)
    }

    func recordingResult(at slot: Int) -> RuntimeRecordingResult {
        rejectInvocation(at: slot)
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

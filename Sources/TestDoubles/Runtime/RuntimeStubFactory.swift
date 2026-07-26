// swiftlint:disable file_length
// The import boundary intentionally makes this the sole home for ABI-facing
// preparation; splitting it would weaken that architectural guarantee.
import InternalRuntimeContract
import TestDoublesRuntime
import TestDoublesRuntimeMetadata

/// The public target's opaque gateway to runtime-generated existential values.
///
/// Construction policy and semantic endpoints stay in `TestDoubles`; this
/// facade keeps the ABI storage type out of public test-double classes.
enum RuntimeStubFactory {
    static func makePayload(
        resources: AnyObject
    ) -> AnyObject {
        TestDoublesRuntimeMetadata.FabricatedPayload(resources: resources)
    }

    static func makeRecordingPlaceholder<T>(for type: T.Type) -> T? {
        PlaceholderValue.make(type)
    }

    static func makeTypedWitnessAdapter<P, Adapter>(
        _ adapter: Adapter,
        invocationType: Stub<P>.Invocation.Type
    ) -> RuntimeTypedWitnessAdapterToken {
        var adapter = adapter
        let word = withUnsafeBytes(of: &adapter) { bytes in
            guard bytes.count >= MemoryLayout<UInt>.size else { return UInt(0) }
            return bytes.load(as: UInt.self)
        }
        let factory = TypedWitnessAdapterFactory(
            functionType: Adapter.self,
            invocationType: invocationType,
            make: { endpoint, slot in
                let invocation = invocationType.init(endpoint: endpoint, slot: slot)
                guard let target = UnsafeRawPointer(bitPattern: word) else {
                    preconditionFailure(
                        "[TestDoubles] A typed witness adapter has no entry point."
                    )
                }
                return TypedWitnessAdapter(target: target, invocation: invocation)
            }
        )
        return RuntimeTypedWitnessAdapterToken(payload: factory)
    }

    struct ProtocolShape {
        private let shape: TestDoublesRuntime.RuntimeStubFactory.ProtocolShape

        fileprivate init(
            shape: TestDoublesRuntime.RuntimeStubFactory.ProtocolShape
        ) {
            self.shape = shape
        }

        var layout: ProtocolLayout { shape.layout }
        var associatedTypeBindings: AssociatedTypeBindings {
            shape.associatedTypeBindings
        }
        var representation: StubExistentialRepresentation {
            shape.representation
        }
    }

    struct Storage<P> {
        private let storage: TestDoublesRuntime.RuntimeStubFactory.Storage<P>

        fileprivate init(
            storage: TestDoublesRuntime.RuntimeStubFactory.Storage<P>
        ) {
            self.storage = storage
        }

        func materialize() -> P {
            storage.materialize()
        }
    }

    /// A prepared fabrication request whose ABI layout stays private to this
    /// facade while its recorder-facing methods remain semantic.
    ///
    /// Preparation is deliberately completed before a public endpoint exists:
    /// the semantic layer can build its recorder from ``methods`` and then
    /// materialize this plan with that endpoint. No layout, descriptor, or
    /// forwarding transport escapes the facade.
    struct PreparedPlan<P> {
        let methods: [RuntimeMethod]
        let modifyDispatches: [Int: RuntimeModifyDispatch]
        private let layout: ProtocolLayout
        private let associatedTypeBindings: AssociatedTypeBindings
        private let representation: StubExistentialRepresentation
        private let descriptors: [MethodDescriptor]
        private let forwarder: (any RuntimeForwarding)?

        fileprivate init(
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
            self.descriptors = descriptors
            self.forwarder = forwarder
            self.modifyDispatches = modifyDispatches
            methods = descriptors.map(\.runtimeMethod)
        }

        fileprivate func materialize(
            endpoint: any RuntimeInvocationEndpoint,
            protocolName: String
        ) throws -> Storage<P> {
            try RuntimeStubFactory.fabricate(
                layout: layout,
                associatedTypeBindings: associatedTypeBindings,
                representation: representation,
                methods: descriptors,
                endpoint: endpoint,
                protocolName: protocolName,
                forwarder: forwarder
            )
        }
    }

    static func preparePlan<P>(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        forwarder: (any RuntimeForwarding)? = nil
    ) throws -> PreparedPlan<P> {
        let modifyDispatches = try TestDoublesRuntime.RuntimeStubFactory.validate(
            methods: methods,
            layout: layout,
            representation: representation
        )
        return PreparedPlan(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            representation: representation,
            descriptors: methods,
            forwarder: forwarder,
            modifyDispatches: modifyDispatches
        )
    }

    static func fabricate<P>(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        endpoint: any RuntimeInvocationEndpoint,
        protocolName: String,
        forwarder: (any RuntimeForwarding)? = nil
    ) throws -> Storage<P> {
        Storage(
            storage: try TestDoublesRuntime.RuntimeStubFactory.fabricate(
                layout: layout,
                associatedTypeBindings: associatedTypeBindings,
                representation: representation,
                methods: methods,
                endpoint: endpoint,
                protocolName: protocolName,
                forwarder: forwarder
            )
        )
    }
}

extension RuntimeStubFactory {
    static func prepareProtocolShape<P>(
        for protocolType: P.Type,
        callerAssociatedTypeBindings: [Stub<P>.AssociatedTypeBinding]
    ) throws -> ProtocolShape {
        let request = RuntimeProtocolShapeRequest(
            protocolType: protocolType,
            typeDescription: String(reflecting: protocolType),
            callerAssociatedTypeBindings: callerAssociatedTypeBindings.map {
                RuntimeAssociatedTypeBindingRequest(
                    declaringProtocol: $0.protocolType,
                    name: $0.name,
                    type: $0.type
                )
            }
        )
        return ProtocolShape(
            shape: try TestDoublesRuntime.RuntimeStubFactory
                .prepareProtocolShape(request)
        )
    }

    static func validateCallerBoundAssociatedTypeUse(
        _ methods: [MethodDescriptor],
        layout: ProtocolLayout
    ) throws {
        try TestDoublesRuntime.RuntimeStubFactory
            .validateCallerBoundAssociatedTypeUse(methods, layout: layout)
    }

    static func singleProtocolDescriptor(
        of type: Any.Type
    ) -> RuntimeProtocolDescriptor? {
        TestDoublesRuntime.RuntimeStubFactory.singleProtocolDescriptor(of: type)
    }

    static func discoverMethods(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        getterEffectPolicy: GetterEffectDiscoveryPolicy
    ) throws -> [MethodDescriptor] {
        try TestDoublesRuntime.RuntimeStubFactory.discoverMethods(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            getterEffectPolicy: getterEffectPolicy
        )
    }

    static func prepareForwarding<P>(
        to target: P,
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation,
        associatedTypeBindings: AssociatedTypeBindings,
        getterEffectPolicy: GetterEffectDiscoveryPolicy
    ) throws -> (
        methods: [MethodDescriptor],
        forwarder: any RuntimeForwarding
    ) {
        try TestDoublesRuntime.RuntimeStubFactory.prepareForwarding(
            to: target,
            layout: layout,
            representation: representation,
            associatedTypeBindings: associatedTypeBindings,
            getterEffectPolicy: getterEffectPolicy
        )
    }

    static func makeExplicitMethodDescriptor(
        schema: RuntimeExplicitRequirementSchema,
        index: Int,
        witnessIndex: Int,
        receiver: StubRequirementReceiver,
        protocolDescriptor: RuntimeProtocolDescriptor,
        bindings: AssociatedTypeBindings,
        containsAssociatedTypes: Bool
    ) throws -> MethodDescriptor {
        try TestDoublesRuntime.RuntimeStubFactory.makeExplicitMethodDescriptor(
            schema: schema,
            index: index,
            witnessIndex: witnessIndex,
            receiver: receiver,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings,
            containsAssociatedTypes: containsAssociatedTypes
        )
    }

    static func validateExplicitRequirementsAgainstLinkedConformances(
        _ methods: [MethodDescriptor],
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings
    ) throws {
        try TestDoublesRuntime.RuntimeStubFactory
            .validateExplicitRequirementsAgainstLinkedConformances(
                methods,
                layout: layout,
                associatedTypeBindings: associatedTypeBindings
            )
    }
}

enum SpyGetterEffectInput<P> {
    case automatic
    case ordered([Stub<P>.GetterEffect])
    case grouped([Stub<P>.ProtocolGetterEffects])
}

/// The error vocabulary for one kind of grouped preparation input.
struct GroupDiagnostics: Sendable {
    let invalidGroup: @Sendable (_ typeDescription: String) -> StubError
    let foreignGroup: @Sendable (_ protocolName: String, _ typeDescription: String) -> StubError
    let duplicateGroup: @Sendable (_ protocolName: String) -> StubError
    let missingGroup: @Sendable (_ protocolName: String) -> StubError

    static let requirements = Self(
        invalidGroup: StubError.invalidProtocolRequirementGroup(typeDescription:),
        foreignGroup: StubError.foreignProtocolRequirementGroup(protocolName:typeDescription:),
        duplicateGroup: StubError.duplicateProtocolRequirementGroup(protocolName:),
        missingGroup: StubError.missingProtocolRequirementGroup(protocolName:)
    )

    static let getterEffects = Self(
        invalidGroup: StubError.invalidProtocolGetterEffectGroup(typeDescription:),
        foreignGroup: StubError.foreignProtocolGetterEffectGroup(protocolName:typeDescription:),
        duplicateGroup: StubError.duplicateProtocolGetterEffectGroup(protocolName:),
        missingGroup: StubError.missingProtocolGetterEffectGroup(protocolName:)
    )
}

extension Stub {
    static func prepareSpy(
        forwardingTo target: P,
        getterEffects input: SpyGetterEffectInput<P>
    ) throws -> PreparedStub {
        let shape = try extractProtocolShape()
        let resolvedGetterEffectPolicy: GetterEffectDiscoveryPolicy
        switch input {
            case .automatic:
                resolvedGetterEffectPolicy = .automatic
            case .ordered(let effects):
                resolvedGetterEffectPolicy = try getterEffectPolicy(
                    effects,
                    layout: shape.layout
                )
            case .grouped(let groups):
                resolvedGetterEffectPolicy = try getterEffectPolicy(
                    groups,
                    layout: shape.layout
                )
        }
        let preparedForwarding = try RuntimeStubFactory.prepareForwarding(
            to: target,
            layout: shape.layout,
            representation: shape.representation,
            associatedTypeBindings: shape.associatedTypeBindings,
            getterEffectPolicy: resolvedGetterEffectPolicy
        )
        return try prepareFabricated(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            methods: preparedForwarding.methods,
            forwarder: preparedForwarding.forwarder
        )
    }

    struct PreparationContext {
        private let shape: RuntimeStubFactory.ProtocolShape

        var layout: ProtocolLayout { shape.layout }
        var bindings: AssociatedTypeBindings { shape.associatedTypeBindings }
        var representation: StubExistentialRepresentation { shape.representation }

        init(shape: RuntimeStubFactory.ProtocolShape) {
            self.shape = shape
        }

        func discoverMethods(
            using getterEffectPolicy: GetterEffectDiscoveryPolicy
        ) throws -> [MethodDescriptor] {
            try RuntimeStubFactory.discoverMethods(
                layout: layout,
                associatedTypeBindings: bindings,
                getterEffectPolicy: getterEffectPolicy
            )
        }

        func descriptors(
            for requirements: [Requirement],
            protocolRequirements: [ProtocolLayout.CallableRequirement]
        ) throws -> [MethodDescriptor] {
            let methods = try zip(requirements, protocolRequirements).map {
                requirement, protocolRequirement in
                try RuntimeStubFactory.makeExplicitMethodDescriptor(
                    schema: requirement.runtimeSchema,
                    index: protocolRequirement.dispatchIndex,
                    witnessIndex: protocolRequirement.witnessIndex,
                    receiver: protocolRequirement.receiver,
                    protocolDescriptor: protocolRequirement.runtimeProtocolDescriptor,
                    bindings: bindings,
                    containsAssociatedTypes: layout.associatedTypeRequirements.isEmpty == false
                )
            }
            for (method, protocolRequirement) in zip(methods, protocolRequirements) {
                guard method.kind == protocolRequirement.kind else {
                    throw StubError.requirementMismatch(
                        protocolName: protocolRequirement.runtimeProtocolDescriptor.name,
                        requirementIndex: protocolRequirement.dispatchIndex,
                        expected: protocolRequirement.kind.rawValue,
                        actual: method.kind.rawValue
                    )
                }
            }
            return methods
        }

        func validateLinkedConformances(
            for methods: [MethodDescriptor]
        ) throws {
            try RuntimeStubFactory.validateExplicitRequirementsAgainstLinkedConformances(
                methods,
                layout: layout,
                associatedTypeBindings: bindings
            )
        }

        func finalize(methods: [MethodDescriptor]) throws -> PreparedStub {
            try Stub.prepareFabricated(
                layout: layout,
                associatedTypeBindings: bindings,
                representation: representation,
                methods: methods
            )
        }
    }

    static func prepare() throws -> PreparedStub {
        let context = PreparationContext(shape: try extractProtocolShape())
        let methods = try context.discoverMethods(using: .automatic)
        return try context.finalize(methods: methods)
    }

    static func prepare(getterEffects: [GetterEffect]) throws -> PreparedStub {
        let context = PreparationContext(shape: try extractProtocolShape())
        let policy = try getterEffectPolicy(
            getterEffects,
            layout: context.layout
        )
        let methods = try context.discoverMethods(using: policy)
        return try context.finalize(methods: methods)
    }

    static func getterEffectPolicy(
        _ getterEffects: [GetterEffect],
        layout: ProtocolLayout
    ) throws -> GetterEffectDiscoveryPolicy {
        guard layout.roots.count == 1 else {
            throw StubError.compositionRequiresGroupedGetterEffects(
                typeDescription: String(reflecting: P.self)
            )
        }
        let hints = try getterEffectHints(
            for: layout.callableRequirements.filter { $0.kind == .getter },
            effects: getterEffects,
            protocolName: layout.roots[0].name
        )
        return .hints(hints)
    }

    static func prepare(
        getterEffectGroups: [ProtocolGetterEffects]
    ) throws -> PreparedStub {
        let context = PreparationContext(shape: try extractProtocolShape())
        let policy = try getterEffectPolicy(
            getterEffectGroups,
            layout: context.layout
        )
        let methods = try context.discoverMethods(using: policy)
        return try context.finalize(methods: methods)
    }

    static func getterEffectPolicy(
        _ getterEffectGroups: [ProtocolGetterEffects],
        layout: ProtocolLayout
    ) throws -> GetterEffectDiscoveryPolicy {
        let matched = try matchGroups(
            getterEffectGroups,
            toDeclaringNodes: layout.nodes.filter {
                $0.callableRequirements.contains { $0.kind == .getter }
            },
            protocolType: \.protocolType,
            items: \.effects,
            diagnostics: .getterEffects
        )

        var hints: [ProtocolLayout.GetterRequirementID: Bool] = [:]
        for (node, effects) in matched {
            hints.merge(
                try getterEffectHints(
                    for: node.callableRequirements.filter { $0.kind == .getter },
                    effects: effects,
                    protocolName: node.descriptor.name
                )
            ) { _, new in new }
        }
        return .hints(hints)
    }

    static func prepare(requirements: [Requirement]) throws -> PreparedStub {
        let context = PreparationContext(shape: try extractProtocolShape())
        let methods = try flatExplicitMethods(requirements, context: context)
        return try context.finalize(methods: methods)
    }

    static func prepare(
        requirementGroups: [ProtocolRequirements]
    ) throws -> PreparedStub {
        let context = PreparationContext(shape: try extractProtocolShape())
        let matched = try matchGroups(
            requirementGroups,
            toDeclaringNodes: context.layout.declaringNodes,
            protocolType: \.protocolType,
            items: \.requirements,
            diagnostics: .requirements
        )

        var methods: [MethodDescriptor] = []
        for (node, requirements) in matched {
            guard requirements.count == node.callableRequirements.count else {
                throw StubError.requirementCountMismatch(
                    protocolName: node.descriptor.name,
                    expected: node.callableRequirements.count,
                    actual: requirements.count
                )
            }
            methods.append(
                contentsOf: try context.descriptors(
                    for: requirements,
                    protocolRequirements: node.callableRequirements
                ))
        }
        methods.sort { $0.index < $1.index }

        try context.validateLinkedConformances(for: methods)
        return try context.finalize(methods: methods)
    }

    /// Resolves flat explicit requirements for a single-root protocol and
    /// validates them against any linked conformance.
    static func flatExplicitMethods(
        _ requirements: [Requirement],
        context: PreparationContext
    ) throws -> [MethodDescriptor] {
        let layout = context.layout
        guard layout.roots.count == 1 else {
            throw StubError.compositionRequiresGroupedRequirements(
                typeDescription: String(reflecting: P.self)
            )
        }
        let protocolRequirements = layout.callableRequirements
        guard requirements.count == protocolRequirements.count else {
            throw StubError.requirementCountMismatch(
                protocolName: layout.roots[0].name,
                expected: protocolRequirements.count,
                actual: requirements.count
            )
        }
        let methods = try context.descriptors(
            for: requirements,
            protocolRequirements: protocolRequirements
        )
        try context.validateLinkedConformances(for: methods)
        return methods
    }

    /// Pairs caller-supplied per-protocol groups with the layout nodes that
    /// declare the grouped items: every group must name exactly one declaring
    /// protocol, and every declaring node must receive exactly one group.
    /// Results preserve layout declaration order.
    private static func matchGroups<Group, Item>(
        _ groups: [Group],
        toDeclaringNodes declaringNodes: [ProtocolLayout.Node],
        protocolType: (Group) -> Any.Type,
        items: (Group) -> [Item],
        diagnostics: GroupDiagnostics
    ) throws -> [(node: ProtocolLayout.Node, items: [Item])] {
        let nodesByID = Dictionary(
            uniqueKeysWithValues: declaringNodes.map {
                (ProtocolLayout.DescriptorID($0.runtimeProtocolDescriptor), $0)
            })
        var suppliedGroups: [ProtocolLayout.DescriptorID: [Item]] = [:]

        for group in groups {
            let groupType = protocolType(group)
            guard let descriptor = singleProtocolDescriptor(of: groupType) else {
                throw diagnostics.invalidGroup(String(reflecting: groupType))
            }
            let identifier = ProtocolLayout.DescriptorID(descriptor)
            guard nodesByID[identifier] != nil else {
                throw diagnostics.foreignGroup(descriptor.name, String(reflecting: P.self))
            }
            guard suppliedGroups[identifier] == nil else {
                throw diagnostics.duplicateGroup(descriptor.name)
            }
            suppliedGroups[identifier] = items(group)
        }

        return try declaringNodes.map { node in
            let identifier = ProtocolLayout.DescriptorID(
                node.runtimeProtocolDescriptor
            )
            guard let items = suppliedGroups[identifier] else {
                throw diagnostics.missingGroup(node.runtimeProtocolDescriptor.name)
            }
            return (node, items)
        }
    }

    private static func getterEffectHints(
        for getters: [ProtocolLayout.CallableRequirement],
        effects: [GetterEffect],
        protocolName: String
    ) throws -> [ProtocolLayout.GetterRequirementID: Bool] {
        guard effects.count == getters.count else {
            throw StubError.getterEffectCountMismatch(
                protocolName: protocolName,
                expected: getters.count,
                actual: effects.count
            )
        }
        return Dictionary(
            uniqueKeysWithValues: zip(getters, effects).map { requirement, effect in
                (
                    ProtocolLayout.GetterRequirementID(
                        protocolDescriptor: requirement.runtimeProtocolDescriptor,
                        witnessIndex: requirement.witnessIndex
                    ),
                    effect.isThrowing
                )
            }
        )
    }

    static func extractProtocolLayout() throws -> ProtocolLayout {
        try extractProtocolShape().layout
    }

    /// Returns the descriptor of the single protocol named by an unbound
    /// existential type, or `nil` for any other runtime type.
    static func singleProtocolDescriptor(
        of type: Any.Type
    ) -> RuntimeProtocolDescriptor? {
        RuntimeStubFactory.singleProtocolDescriptor(of: type)
    }

}

extension Stub {
    static func prepareFabricated(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        representation: StubExistentialRepresentation,
        methods: [MethodDescriptor],
        forwarder: (any RuntimeForwarding)? = nil
    ) throws -> PreparedStub {
        let plan: RuntimeStubFactory.PreparedPlan<P> = try RuntimeStubFactory.preparePlan(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            representation: representation,
            methods: methods,
            forwarder: forwarder
        )

        let recorder = StubRecorder(
            methods: plan.methods,
            modifyDispatchDescriptors: plan.modifyDispatches,
            allowsForwardingFallback: forwarder != nil
        )
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)
        let protocolName = String(reflecting: P.self)
        let storage = try plan.materialize(
            endpoint: endpoint,
            protocolName: protocolName
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

/// Runs a runtime test-double construction operation while preserving the
/// public `StubError` failure contract.
///
/// Construction helpers predate typed throws but are required to report only
/// `StubError`. Any other error indicates an internal invariant violation and
/// fails closed instead of escaping through the public API as `any Error`.
func withStubConstructionError<Result>(
    for protocolType: Any.Type,
    _ operation: () throws -> Result
) throws(StubError) -> Result {
    do {
        return try operation()
    } catch let error as StubError {
        throw error
    } catch let error as RuntimeConstructionError {
        throw StubError(error)
    } catch {
        preconditionFailure(
            "[TestDoubles] Construction for '\(String(reflecting: protocolType))' "
                + "threw unexpected internal error type "
                + "'\(String(reflecting: Swift.type(of: error)))': \(error)"
        )
    }
}

enum TestDoubleConstructionKind: String {
    case dummy
    case spy
    case stub
}

func constructTestDoubleOrFail<Result>(
    _ kind: TestDoubleConstructionKind,
    for protocolType: Any.Type,
    _ operation: () throws(StubError) -> Result
) -> Result {
    do {
        return try operation()
    } catch {
        fatalError(
            "[TestDoubles] Could not construct a \(kind.rawValue) for "
                + "'\(String(reflecting: protocolType))': \(error)"
        )
    }
}

extension StubError {
    /// Converts a package-only runtime construction failure into the stable
    /// public error vocabulary without leaking the runtime error type.
    init(_ runtimeError: RuntimeConstructionError) {
        switch runtimeError {
            case .typeIsNotProtocol(let typeDescription):
                self = .typeIsNotProtocol(typeDescription: typeDescription)
            case .unsupportedTypeKind(let typeName):
                self = .unsupportedTypeKind(typeName: typeName)
            case .unsupportedProtocolShape(let protocolName, let reason):
                self = .unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: reason
                )
            case .noConformanceFound(let protocolName):
                self = .noConformanceFound(protocolName: protocolName)
            case .signatureDiscoveryFailed(
                let protocolName,
                let requirementIndex,
                let details
            ):
                self = .signatureDiscoveryFailed(
                    protocolName: protocolName,
                    requirementIndex: requirementIndex,
                    details: details
                )
            case .requirementCountMismatch(
                let protocolName,
                let expected,
                let actual
            ):
                self = .requirementCountMismatch(
                    protocolName: protocolName,
                    expected: expected,
                    actual: actual
                )
            case .requirementMismatch(
                let protocolName,
                let requirementIndex,
                let expected,
                let actual
            ):
                self = .requirementMismatch(
                    protocolName: protocolName,
                    requirementIndex: requirementIndex,
                    expected: expected,
                    actual: actual
                )
            case .forwardingUnsupported(let protocolName, let reason):
                self = .unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: Self.forwardingDiagnostic(reason)
                )
            case .trampolineAllocationFailed(let requirementIndex):
                self = .trampolineAllocationFailed(
                    requirementIndex: requirementIndex
                )
        }
    }

    private static func forwardingDiagnostic(
        _ reason: RuntimeForwardingUnsupportedReason
    ) -> String {
        switch reason {
            case .pairedLegacyReadAndYieldingBorrow:
                return "Forwarding Spy does not yet support Swift 6.4's paired legacy read and yielding-borrow witnesses. Use a Stub or a hand-written spy."
            case .nonInstanceRequirement(let index):
                return "Forwarding Spy supports instance requirements only; requirement \(index) uses a metatype receiver."
            case .simd(let index):
                return "Forwarding Spy does not yet support SIMD arguments or results in requirement \(index)."
            case .functionValues(let index):
                return "Forwarding Spy does not yet support function-valued arguments or results in requirement \(index)."
            case .outgoingStackWords(let index, let limit):
                return "Forwarding Spy requirement \(index) needs more outgoing stack transport than \(limit) words support. Use fewer arguments or a hand-written spy."
            case .dynamicSelfResult(let index):
                return "Forwarding Spy does not yet support dynamic Self results in requirement \(index)."
            case .selfArguments(let index):
                return "Forwarding Spy does not support direct or Optional Self arguments in requirement \(index). Use an automatic Stub or a hand-written spy."
            case .hiddenArguments(let index):
                return "Forwarding Spy requirement \(index) uses stack arguments or leaves no registers for its target metadata and witness table. Use fewer arguments or a hand-written spy."
        }
    }
}

extension Stub {
    static func extractProtocolShape(
        callerAssociatedTypeBindings: [AssociatedTypeBinding] = []
    ) throws -> RuntimeStubFactory.ProtocolShape {
        try RuntimeStubFactory.prepareProtocolShape(
            for: P.self,
            callerAssociatedTypeBindings: callerAssociatedTypeBindings
        )
    }

    static func prepare(
        callerAssociatedTypeBindings: [AssociatedTypeBinding],
        requirements: [Requirement]
    ) throws -> PreparedStub {
        let context = PreparationContext(
            shape: try extractProtocolShape(
                callerAssociatedTypeBindings: callerAssociatedTypeBindings
            )
        )
        let methods =
            if requirements.isEmpty {
                try context.discoverMethods(using: .automatic)
            } else {
                try flatExplicitMethods(requirements, context: context)
            }

        try RuntimeStubFactory.validateCallerBoundAssociatedTypeUse(
            methods,
            layout: context.layout
        )
        return try context.finalize(methods: methods)
    }
}

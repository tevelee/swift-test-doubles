import Echo

enum SpyGetterEffectInput<P> {
    case automatic
    case ordered([Stub<P>.GetterEffect])
    case grouped([Stub<P>.ProtocolGetterEffects])
}

struct StubProtocolShape {
    let layout: ProtocolLayout
    let associatedTypeBindings: AssociatedTypeBindings
    let representation: StubExistentialRepresentation
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
        let forwardingTarget = try ForwardingTarget(
            target,
            layout: shape.layout,
            representation: shape.representation
        )
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
        let methods = try discoverMethods(
            witnessTables: forwardingTarget.witnessTables,
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            getterEffectPolicy: resolvedGetterEffectPolicy
        )
        let forwarder = try ProtocolForwarder(
            target: forwardingTarget,
            methods: methods,
            layout: shape.layout
        )
        return try prepareFabricated(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            methods: methods,
            forwarder: forwarder
        )
    }

    struct PreparationContext {
        private let shape: StubProtocolShape

        var layout: ProtocolLayout { shape.layout }
        var bindings: AssociatedTypeBindings { shape.associatedTypeBindings }
        var representation: StubExistentialRepresentation { shape.representation }

        init(shape: StubProtocolShape) {
            self.shape = shape
        }

        func discoverMethods(
            using getterEffectPolicy: GetterEffectDiscoveryPolicy
        ) throws -> [MethodDescriptor] {
            let witnessTables = try LinkedWitnessTableGraph.discover(in: layout)
            return try TestDoubles.discoverMethods(
                witnessTables: witnessTables,
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
                try requirement.descriptor(
                    index: protocolRequirement.dispatchIndex,
                    witnessIndex: protocolRequirement.witnessIndex,
                    receiver: protocolRequirement.receiver,
                    protocolDescriptor: protocolRequirement.protocolDescriptor,
                    bindings: bindings,
                    containsAssociatedTypes: layout.associatedTypeRequirements.isEmpty == false
                )
            }
            for (method, protocolRequirement) in zip(methods, protocolRequirements) {
                guard method.kind == protocolRequirement.kind else {
                    throw StubError.requirementMismatch(
                        protocolName: protocolRequirement.protocolDescriptor.name,
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
            try Stub.validateAgainstLinkedConformances(
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
                (ProtocolLayout.DescriptorID($0.descriptor), $0)
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
            let identifier = ProtocolLayout.DescriptorID(node.descriptor)
            guard let items = suppliedGroups[identifier] else {
                throw diagnostics.missingGroup(node.descriptor.name)
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
                        protocolDescriptor: requirement.protocolDescriptor,
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
    static func singleProtocolDescriptor(of type: Any.Type) -> ProtocolDescriptor? {
        guard let existential = reflect(type) as? ExistentialMetadata,
            existential.protocols.count == 1
        else {
            return nil
        }
        return existential.protocols[0]
    }

}

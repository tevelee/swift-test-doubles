import InternalRuntimeContract
import TestDoublesRuntimeMetadata
/// Runtime preparation operations behind the opaque stub-factory boundary.
///
/// The public target supplies contract-level requirement schemas and effect
/// hints. This extension owns their layout matching, linked-witness discovery,
/// signature resolution, validation, and forwarding transport construction.
extension RuntimeStubFactory {
    /// Resolves source-level stub input into an opaque runtime plan.
    package static func prepareStub<P>(
        _ request: RuntimeStubPreparationRequest
    ) throws -> PreparedPlan<P> {
        let cacheKey = PreparedStubPlanCache.key(for: request)
        if let cacheKey,
            let cached: PreparedPlan<P> = PreparedStubPlanCache.plan(
                for: cacheKey
            )
        {
            return cached
        }
        let shape = try prepareProtocolShape(request.shape)
        let methods = try methods(
            for: request.requirements,
            getterEffects: request.getterEffects,
            shape: shape,
            typeDescription: request.shape.typeDescription
        )
        if request.shape.callerAssociatedTypeBindings.isEmpty == false {
            try validateCallerBoundAssociatedTypeUse(methods, layout: shape.layout)
        }
        let plan: PreparedPlan<P> = try preparedPlan(
            shape: shape,
            methods: methods,
            forwarder: nil
        )
        guard let cacheKey else { return plan }
        return PreparedStubPlanCache.insert(plan, for: cacheKey)
    }

    /// Resolves a forwarding target and source-level getter hints into an
    /// opaque runtime plan.
    package static func prepareForwardingStub<P>(
        to target: P,
        request: RuntimeStubPreparationRequest
    ) throws -> PreparedPlan<P> {
        let shape = try prepareProtocolShape(request.shape)
        let getterEffectPolicy = try getterEffectPolicy(
            request.getterEffects,
            layout: shape.layout,
            typeDescription: request.shape.typeDescription
        )
        let forwarding = try prepareForwarding(
            to: target,
            layout: shape.layout,
            representation: shape.representation,
            associatedTypeBindings: shape.associatedTypeBindings,
            getterEffectPolicy: getterEffectPolicy
        )
        return try preparedPlan(
            shape: shape,
            methods: forwarding.methods,
            forwarder: forwarding.forwarder
        )
    }

    /// Resolves a dummy's protocol shape while retaining its witness details
    /// inside the runtime. The caller receives presentation-ready diagnostics
    /// keyed by semantic dispatch slot.
    package static func prepareDummy<P>(
        _ request: RuntimeProtocolShapeRequest
    ) throws -> PreparedDummyPlan<P> {
        let shape = try prepareProtocolShape(request)
        let requirements = shape.layout.callableRequirements.map { requirement in
            RuntimeDummyRequirement(
                slot: requirement.dispatchIndex,
                description: "\(requirement.protocolDescriptor.name) \(requirement.kind.rawValue) requirement at witness index \(requirement.witnessIndex)"
            )
        }
        return PreparedDummyPlan(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            requirements: requirements
        )
    }

    private static func preparedPlan<P>(
        shape: ProtocolShape,
        methods: [MethodDescriptor],
        forwarder: (any RuntimeForwarding)?
    ) throws -> PreparedPlan<P> {
        let modifyDispatches = try validate(
            methods: methods,
            layout: shape.layout,
            representation: shape.representation
        )
        return PreparedPlan(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            descriptors: methods,
            forwarder: forwarder,
            modifyDispatches: modifyDispatches
        )
    }

    private static func methods(
        for input: RuntimeExplicitRequirementInput,
        getterEffects: RuntimeGetterEffectInput,
        shape: ProtocolShape,
        typeDescription: String
    ) throws -> [MethodDescriptor] {
        switch input {
            case .automatic:
                return try discoverMethods(
                    layout: shape.layout,
                    associatedTypeBindings: shape.associatedTypeBindings,
                    getterEffectPolicy: try getterEffectPolicy(
                        getterEffects,
                        layout: shape.layout,
                        typeDescription: typeDescription
                    )
                )

            case .flat(let requirements):
                guard shape.layout.roots.count == 1 else {
                    throw RuntimeConstructionError.compositionRequiresGroupedRequirements(
                        typeDescription: typeDescription
                    )
                }
                let methods = try explicitMethods(
                    requirements,
                    protocolRequirements: shape.layout.callableRequirements,
                    shape: shape
                )
                try validateExplicitRequirementsAgainstLinkedConformances(
                    methods,
                    layout: shape.layout,
                    associatedTypeBindings: shape.associatedTypeBindings
                )
                return methods

            case .grouped(let groups):
                let matched = try matchGroups(
                    groups,
                    toDeclaringNodes: shape.layout.declaringNodes,
                    protocolType: \.declaringProtocol,
                    items: \.requirements,
                    typeDescription: typeDescription,
                    diagnostics: .requirements
                )
                var methods: [MethodDescriptor] = []
                for (node, requirements) in matched {
                    guard requirements.count == node.callableRequirements.count else {
                        throw RuntimeConstructionError.requirementCountMismatch(
                            protocolName: node.descriptor.name,
                            expected: node.callableRequirements.count,
                            actual: requirements.count
                        )
                    }
                    methods.append(
                        contentsOf: try explicitMethods(
                            requirements,
                            protocolRequirements: node.callableRequirements,
                            shape: shape
                        ))
                }
                methods.sort { $0.index < $1.index }
                try validateExplicitRequirementsAgainstLinkedConformances(
                    methods,
                    layout: shape.layout,
                    associatedTypeBindings: shape.associatedTypeBindings
                )
                return methods
        }
    }

    private static func explicitMethods(
        _ requirements: [RuntimeExplicitRequirementSchema],
        protocolRequirements: [ProtocolLayout.CallableRequirement],
        shape: ProtocolShape
    ) throws -> [MethodDescriptor] {
        guard requirements.count == protocolRequirements.count else {
            let protocolName =
                protocolRequirements.first?.protocolDescriptor.name
                ?? shape.layout.roots[0].name
            throw RuntimeConstructionError.requirementCountMismatch(
                protocolName: protocolName,
                expected: protocolRequirements.count,
                actual: requirements.count
            )
        }
        let methods = try zip(requirements, protocolRequirements).map {
            requirement, protocolRequirement in
            try makeExplicitMethodDescriptor(
                schema: requirement,
                index: protocolRequirement.dispatchIndex,
                witnessIndex: protocolRequirement.witnessIndex,
                receiver: protocolRequirement.receiver,
                protocolDescriptor: protocolRequirement.runtimeProtocolDescriptor,
                bindings: shape.associatedTypeBindings,
                containsAssociatedTypes: shape.layout.associatedTypeRequirements.isEmpty == false
            )
        }
        for (method, requirement) in zip(methods, protocolRequirements) {
            guard method.kind == requirement.kind else {
                throw RuntimeConstructionError.requirementMismatch(
                    protocolName: requirement.runtimeProtocolDescriptor.name,
                    requirementIndex: requirement.dispatchIndex,
                    expected: requirement.kind.rawValue,
                    actual: method.kind.rawValue
                )
            }
        }
        return methods
    }

    private static func getterEffectPolicy(
        _ input: RuntimeGetterEffectInput,
        layout: ProtocolLayout,
        typeDescription: String
    ) throws -> GetterEffectDiscoveryPolicy {
        switch input {
            case .automatic:
                return .automatic
            case .flat(let effects):
                guard layout.roots.count == 1 else {
                    throw RuntimeConstructionError.compositionRequiresGroupedGetterEffects(
                        typeDescription: typeDescription
                    )
                }
                return .hints(
                    try getterEffectHints(
                        for: layout.callableRequirements.filter { $0.kind == .getter },
                        effects: effects,
                        protocolName: layout.roots[0].name
                    ))
            case .grouped(let groups):
                let matched = try matchGroups(
                    groups,
                    toDeclaringNodes: layout.nodes.filter {
                        $0.callableRequirements.contains { $0.kind == .getter }
                    },
                    protocolType: \.declaringProtocol,
                    items: \.effects,
                    typeDescription: typeDescription,
                    diagnostics: .getterEffects
                )
                var hints: [ProtocolLayout.GetterRequirementID: GetterEffectHint] = [:]
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
    }

    private static func getterEffectHints(
        for getters: [ProtocolLayout.CallableRequirement],
        effects: [RuntimeGetterEffectHint],
        protocolName: String
    ) throws -> [ProtocolLayout.GetterRequirementID: GetterEffectHint] {
        guard effects.count == getters.count else {
            throw RuntimeConstructionError.getterEffectCountMismatch(
                protocolName: protocolName,
                expected: getters.count,
                actual: effects.count
            )
        }
        return Dictionary(
            uniqueKeysWithValues: zip(getters, effects).map {
                requirement, effect in
                (
                    ProtocolLayout.GetterRequirementID(
                        protocolDescriptor: requirement.runtimeProtocolDescriptor,
                        witnessIndex: requirement.witnessIndex
                    ),
                    GetterEffectHint(
                        isThrowing: effect.isThrowing,
                        typedErrorType: effect.typedErrorType
                    )
                )
            })
    }

    private enum GroupDiagnostics {
        case requirements
        case getterEffects

        func invalid(typeDescription: String) -> RuntimeConstructionError {
            switch self {
                case .requirements:
                    .invalidProtocolRequirementGroup(typeDescription: typeDescription)
                case .getterEffects:
                    .invalidProtocolGetterEffectGroup(typeDescription: typeDescription)
            }
        }

        func foreign(
            protocolName: String,
            typeDescription: String
        ) -> RuntimeConstructionError {
            switch self {
                case .requirements:
                    .foreignProtocolRequirementGroup(
                        protocolName: protocolName,
                        typeDescription: typeDescription
                    )
                case .getterEffects:
                    .foreignProtocolGetterEffectGroup(
                        protocolName: protocolName,
                        typeDescription: typeDescription
                    )
            }
        }

        func duplicate(protocolName: String) -> RuntimeConstructionError {
            switch self {
                case .requirements:
                    .duplicateProtocolRequirementGroup(protocolName: protocolName)
                case .getterEffects:
                    .duplicateProtocolGetterEffectGroup(protocolName: protocolName)
            }
        }

        func missing(protocolName: String) -> RuntimeConstructionError {
            switch self {
                case .requirements:
                    .missingProtocolRequirementGroup(protocolName: protocolName)
                case .getterEffects:
                    .missingProtocolGetterEffectGroup(protocolName: protocolName)
            }
        }
    }

    private static func matchGroups<Group, Item>(
        _ groups: [Group],
        toDeclaringNodes declaringNodes: [ProtocolLayout.Node],
        protocolType: (Group) -> Any.Type,
        items: (Group) -> [Item],
        typeDescription: String,
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
                throw diagnostics.invalid(typeDescription: String(reflecting: groupType))
            }
            let identifier = ProtocolLayout.DescriptorID(descriptor)
            guard nodesByID[identifier] != nil else {
                throw diagnostics.foreign(
                    protocolName: descriptor.name,
                    typeDescription: typeDescription
                )
            }
            guard suppliedGroups[identifier] == nil else {
                throw diagnostics.duplicate(protocolName: descriptor.name)
            }
            suppliedGroups[identifier] = items(group)
        }

        return try declaringNodes.map { node in
            let identifier = ProtocolLayout.DescriptorID(node.runtimeProtocolDescriptor)
            guard let items = suppliedGroups[identifier] else {
                throw diagnostics.missing(protocolName: node.runtimeProtocolDescriptor.name)
            }
            return (node, items)
        }
    }

    package static func discoverMethods(
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        getterEffectPolicy: GetterEffectDiscoveryPolicy
    ) throws -> [MethodDescriptor] {
        try TestDoublesRuntimeMetadata.discoverMethods(
            witnessTables: try LinkedWitnessTableGraph.discover(in: layout),
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            getterEffectPolicy: getterEffectPolicy
        )
    }

    package static func prepareForwarding<P>(
        to target: P,
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation,
        associatedTypeBindings: AssociatedTypeBindings,
        getterEffectPolicy: GetterEffectDiscoveryPolicy
    ) throws -> (
        methods: [MethodDescriptor],
        forwarder: any RuntimeForwarding
    ) {
        let forwardingTarget = try ForwardingTarget(
            target,
            layout: layout,
            representation: representation
        )
        let methods = try TestDoublesRuntimeMetadata.discoverMethods(
            witnessTables: forwardingTarget.witnessTables,
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            getterEffectPolicy: getterEffectPolicy
        )
        let forwarder = try ProtocolForwarder(
            target: forwardingTarget,
            methods: methods,
            layout: layout
        )
        return (methods, forwarder)
    }

    package static func makeExplicitMethodDescriptor(
        schema: RuntimeExplicitRequirementSchema,
        index: Int,
        witnessIndex: Int,
        receiver: StubRequirementReceiver,
        protocolDescriptor: RuntimeProtocolDescriptor,
        bindings: AssociatedTypeBindings,
        containsAssociatedTypes: Bool
    ) throws -> MethodDescriptor {
        try TestDoublesRuntimeMetadata.makeExplicitMethodDescriptor(
            schema: schema,
            index: index,
            witnessIndex: witnessIndex,
            receiver: receiver,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings,
            containsAssociatedTypes: containsAssociatedTypes
        )
    }

    package static func validateExplicitRequirementsAgainstLinkedConformances(
        _ methods: [MethodDescriptor],
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings
    ) throws {
        try TestDoublesRuntimeMetadata.validateExplicitRequirementsAgainstLinkedConformances(
            methods,
            layout: layout,
            associatedTypeBindings: associatedTypeBindings
        )
    }

}

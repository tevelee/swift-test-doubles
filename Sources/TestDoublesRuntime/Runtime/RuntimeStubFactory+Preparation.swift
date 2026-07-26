import TestDoublesRuntimeMetadata
/// Runtime preparation operations behind the opaque stub-factory boundary.
///
/// The public target selects requirement order, getter-effect policy, and
/// diagnostics. This extension owns all linked-witness discovery, signature
/// resolution, and forwarding transport construction.
extension RuntimeStubFactory {
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

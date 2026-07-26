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

import InternalRuntimeContract
import TestDoublesRuntime

/// The public target's opaque gateway to runtime-generated existential values.
///
/// Construction policy and semantic endpoints stay in `TestDoubles`; this
/// facade keeps the ABI storage type out of public test-double classes.
enum RuntimeStubFactory {
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

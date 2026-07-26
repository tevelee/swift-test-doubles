import InternalRuntimeContract

extension Stub.Requirement {
    static func typedAdapter<Adapter>(
        _ adapter: Adapter
    ) -> RuntimeTypedWitnessAdapterToken {
        RuntimeStubFactory.makeTypedWitnessAdapter(
            adapter,
            invocationType: Stub<P>.Invocation.self
        )
    }
}

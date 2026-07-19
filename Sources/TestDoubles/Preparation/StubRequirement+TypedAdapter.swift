extension Stub.Requirement {
    static func typedAdapterFactory<Adapter>(
        _ adapter: Adapter
    ) -> TypedWitnessAdapterFactory {
        var adapter = adapter
        let word = withUnsafeBytes(of: &adapter) { bytes in
            guard bytes.count >= MemoryLayout<UInt>.size else { return UInt(0) }
            return bytes.load(as: UInt.self)
        }
        return TypedWitnessAdapterFactory(
            functionType: Adapter.self,
            invocationType: Stub<P>.Invocation.self,
            make: { recorder, method in
                let invocation = Stub<P>.Invocation(recorder: recorder, method: method)
                guard let target = UnsafeRawPointer(bitPattern: word) else {
                    preconditionFailure("[TestDoubles] A typed witness adapter has no entry point.")
                }
                return TypedWitnessAdapter(
                    target: target,
                    invocationArgumentIndex: typedAdapterArgumentIndex(for: method),
                    invocation: invocation
                )
            }
        )
    }
}

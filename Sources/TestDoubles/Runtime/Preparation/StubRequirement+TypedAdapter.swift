import InternalRuntimeContract
import TestDoublesRuntime
import TestDoublesRuntimeMetadata
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
            make: { endpoint, slot in
                let invocation = Stub<P>.Invocation(endpoint: endpoint, slot: slot)
                guard let target = UnsafeRawPointer(bitPattern: word) else {
                    preconditionFailure("[TestDoubles] A typed witness adapter has no entry point.")
                }
                return TypedWitnessAdapter(
                    target: target,
                    invocation: invocation
                )
            }
        )
    }
}

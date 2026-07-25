/// Construction-time ABI plans for one fabricated witness requirement.
///
/// Both argument decoding variants are precomputed so forwarding can borrow
/// arguments while a configured override consumes them without rebuilding
/// metadata during an invocation.
package final class PreparedRuntimeMethod: @unchecked Sendable {
    package let descriptor: MethodDescriptor
    package let consumingDecodingPlan: RuntimeArgumentDecodingPlan
    package let borrowedDecodingPlan: RuntimeArgumentDecodingPlan
    package let resultTransport: RuntimeResultTransportPlan
    package let asyncStackAdjustmentByteCount: Int?

    package init(_ descriptor: MethodDescriptor) {
        self.descriptor = descriptor
        let decodingTransport = WitnessCallTransportPlan(method: descriptor)
        consumingDecodingPlan = RuntimeArgumentDecodingPlan.witness(
            method: descriptor,
            transport: decodingTransport,
            consumeOwnedArguments: true
        )
        borrowedDecodingPlan = RuntimeArgumentDecodingPlan.witness(
            method: descriptor,
            transport: decodingTransport,
            consumeOwnedArguments: false
        )
        resultTransport = RuntimeResultTransportPlan(
            resultType: descriptor.returnType
        )
        asyncStackAdjustmentByteCount =
            descriptor.isAsync
            ? asyncWitnessStackPlan(
                for: descriptor,
                architecture: .current
            ).stackAdjustmentByteCount
            : nil
    }
}

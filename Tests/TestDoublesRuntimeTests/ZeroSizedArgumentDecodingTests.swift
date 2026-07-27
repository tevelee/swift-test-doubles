import Testing
@testable import TestDoublesRuntime

private struct EmptyTransportValue: Equatable {}

@Suite struct ZeroSizedArgumentDecodingTests {
    @Test func declaredVoidAndEmptyStructTypesSurviveBothDecoders() {
        let types: [Any.Type] = [Void.self, EmptyTransportValue.self]

        expectDynamicTypes(decodeWitnessArguments(types), equal: types)
        expectDynamicTypes(decodeDynamicArguments(types), equal: types)
    }

    @available(macOS 26.0, *)
    @Test func emptyInlineArrayTypeSurvivesBothDecoders() {
        let type = InlineArray<0, Int>.self

        expectDynamicTypes(decodeWitnessArguments([type]), equal: [type])
        expectDynamicTypes(decodeDynamicArguments([type]), equal: [type])
    }

    private func decodeWitnessArguments(_ types: [Any.Type]) -> [Any] {
        let method = MethodDescriptor(
            kind: .method,
            name: "zeroSized",
            index: 0,
            argumentTypes: types,
            returnType: Void.self
        )
        let call = ManagedDynamicCall(resultType: Void.self, errorType: nil)
        return RuntimeArgumentDecoder.decode(
            for: method,
            from: call.frame,
            consumeOwnedArguments: false
        ).values
    }

    private func decodeDynamicArguments(_ types: [Any.Type]) -> [Any] {
        let plan = DynamicFunctionArgumentDecodingPlan(
            parameterTypes: types,
            typedErrorUsesIndirectResultSlot: false
        )
        let call = ManagedDynamicCall(resultType: Void.self, errorType: nil)
        return plan.decode(from: call.frame).values
    }

    private func expectDynamicTypes(
        _ values: [Any],
        equal types: [Any.Type]
    ) {
        #expect(values.count == types.count)
        for (value, type) in zip(values, types) {
            #expect(
                ObjectIdentifier(Swift.type(of: value))
                    == ObjectIdentifier(type)
            )
        }
    }
}

import Testing
@testable import TestDoubles

private struct WideTransportValue: Equatable {
    let first: Int
    let second: Int
    let third: Int
}

private enum TransportError: Error, Equatable {
    case rejected(Int)
}

private struct WideTransportError: Error, Equatable {
    let first: Int
    let second: Int
    let third: Int
}

@Suite struct RuntimeValueTransportTests {
    @Test func resultPlansPrecomputeFunctionReabstraction() {
        typealias Closure = (Int) -> Int
        typealias NestedClosure = (Int, Closure?)

        #expect(
            RuntimeResultTransportPlan(resultType: Int.self)
                .requiresFunctionReabstraction == false
        )
        #expect(
            RuntimeResultTransportPlan(resultType: Closure.self)
                .requiresFunctionReabstraction
        )
        #expect(
            RuntimeResultTransportPlan(resultType: NestedClosure.self)
                .requiresFunctionReabstraction
        )
    }

    @Test func directIntegerAndFloatingPointResultsRoundTripThroughTheFrame() {
        #expect(roundTrip(42) == 42)
        #expect(roundTrip(3.25) == 3.25)
    }

    @Test func directAggregateResultsRoundTripThroughTheirRegisterParts() {
        let value = (3.5, 42)
        let result = roundTrip(value)

        #expect(result.0 == value.0)
        #expect(result.1 == value.1)
    }

    @Test func indirectResultsInitializeCallerOwnedStorage() {
        let value = WideTransportValue(first: 1, second: 2, third: 3)

        #expect(roundTrip(value) == value)
    }

    private func roundTrip<Value>(_ value: Value) -> Value {
        let layout = abiClass(for: Value.self, isReturn: true)
        let call = ManagedDynamicCall(resultType: Value.self, errorType: nil)
        if case .indirect = layout {
            call.frame.storeIndirectResultAddress(
                UInt(bitPattern: call.result.storage)
            )
        }
        RuntimeValueTransport.encodeReturn(
            value,
            expectedType: Value.self,
            layout: layout,
            context: "transport test",
            isAsync: false,
            into: call.frame
        )
        call.finish(
            resultLayout: layout,
            typedErrorLayout: nil,
            typedErrorUsesIndirectResultSlot: false
        )
        return call.result.moveInitializedValue(as: Value.self)
    }
}

@Suite struct SwiftErrorTransportTests {
    @Test func untypedErrorsTransferOwnershipThroughSwiftErrorStorage() throws {
        let call = ManagedDynamicCall(resultType: Void.self, errorType: nil)

        SwiftErrorTransport.encode(TransportError.rejected(42), into: call.frame)
        let error = try #require(
            SwiftErrorTransport.take(call.frame.returnedError) as? TransportError
        )

        #expect(error == .rejected(42))
    }

    @Test func directTypedErrorsUseReturnRegisters() {
        let error = TransportError.rejected(7)

        #expect(roundTripTyped(error, usesIndirectResultSlot: false) == error)
    }

    @Test func indirectTypedErrorsInitializeTheirDedicatedBuffer() {
        let error = WideTransportError(first: 1, second: 2, third: 3)

        #expect(roundTripTyped(error, usesIndirectResultSlot: true) == error)
    }

    private func roundTripTyped<Failure: Error>(
        _ error: Failure,
        usesIndirectResultSlot: Bool
    ) -> Failure {
        let layout = abiClass(for: Failure.self, isReturn: true)
        let call = ManagedDynamicCall(
            resultType: Void.self,
            errorType: Failure.self
        )
        let destination = usesIndirectResultSlot ? call.error?.storage : nil
        SwiftErrorTransport.encodeTyped(
            error,
            expectedType: Failure.self,
            layout: layout,
            destination: destination,
            usesIndirectResultSlot: usesIndirectResultSlot,
            context: "typed-error transport test",
            missingDestinationMessage: "missing typed-error test buffer",
            isAsync: false,
            into: call.frame
        )
        call.finish(
            resultLayout: .void,
            typedErrorLayout: layout,
            typedErrorUsesIndirectResultSlot: usesIndirectResultSlot
        )
        return call.error!.moveInitializedValue(as: Failure.self)
    }
}

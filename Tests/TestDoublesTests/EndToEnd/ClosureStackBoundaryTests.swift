import TestDoubles
import TestDoublesFixtures
import Testing

@Suite struct ClosureStackBoundaryTests {
    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func returnedSynchronousClosuresTransportOneStackWord() throws {
        _ = RealExternalClosureStackBridgeService()
        let placeholder = externalStackSyncClosure(offset: 0)
        let result = externalStackSyncClosure(offset: 100)
        let stub = try Stub<any ExternalClosureStackBridgeService>()

        stub.when(returning: placeholder) {
            $0.synchronous()
        }.thenReturn(result)

        let value: any ExternalClosureStackBridgeService = stub()
        #expect(
            externalInvokeStackSync(value.synchronous())
                == externalInvokeStackSync(placeholder) + 100
        )
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func returnedTypedThrowingClosuresSpillTheirErrorDestination() throws {
        _ = RealExternalClosureStackBridgeService()
        let failure = ExternalLargeClosureError(
            first: 11,
            second: 12,
            third: 13,
            fourth: 14
        )
        let placeholder = externalStackTypedClosure(
            offset: 0,
            failure: failure
        )
        let result = externalStackTypedClosure(
            offset: 100,
            failure: failure
        )
        let stub = try Stub<any ExternalClosureStackBridgeService>()
        stub.when(returning: placeholder) {
            $0.typedThrowing()
        }.thenReturn(result)

        let value: any ExternalClosureStackBridgeService = stub()
        #expect(
            try externalInvokeStackTyped(value.typedThrowing(), first: 1)
                == externalInvokeStackTyped(placeholder, first: 1) + 100
        )
        #expect(throws: failure) {
            _ = try externalInvokeStackTyped(value.typedThrowing(), first: 0)
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func returnedAsyncClosuresCopyTheirStackWordBeforeSuspending() async throws {
        _ = RealExternalClosureStackBridgeService()
        let placeholder = externalStackAsyncClosure(offset: 0)
        let result = externalStackAsyncClosure(offset: 100)
        let stub = try Stub<any ExternalClosureStackBridgeService>()
        stub.when(returning: placeholder) {
            $0.asynchronous()
        }.thenReturn(result)

        let value: any ExternalClosureStackBridgeService = stub()
        let actual = await externalInvokeStackAsync(value.asynchronous())
        let baseline = await externalInvokeStackAsync(placeholder)
        #expect(actual.first == baseline.first + 100)
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func returnedAsyncTypedClosuresSpillResultAndErrorDestinations() async throws {
        _ = RealExternalClosureStackBridgeService()
        let failure = ExternalLargeClosureError(
            first: 11,
            second: 12,
            third: 13,
            fourth: 14
        )
        let placeholder = externalStackAsyncTypedClosure(
            offset: 0,
            failure: failure
        )
        let result = externalStackAsyncTypedClosure(
            offset: 100,
            failure: failure
        )
        let stub = try Stub<any ExternalClosureStackBridgeService>()
        stub.when(returning: placeholder) {
            $0.asyncTypedThrowing()
        }.thenReturn(result)

        let value: any ExternalClosureStackBridgeService = stub()
        let actual = try await externalInvokeStackAsyncTyped(
            value.asyncTypedThrowing(),
            first: 1
        )
        let baseline = try await externalInvokeStackAsyncTyped(
            placeholder,
            first: 1
        )
        #expect(actual.first == baseline.first + 100)
        await #expect(throws: failure) {
            _ = try await externalInvokeStackAsyncTyped(
                value.asyncTypedThrowing(),
                first: 0
            )
        }
    }

    @available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
    @Test func sixParameterInputsStageOneOwnedStackWordBeforeInvocation() async throws {
        _ = RealExternalClosureStackBridgeService()
        let directPlaceholder = externalDirectStackInputClosure(offset: 0)
        let asyncPlaceholder = externalDirectAsyncStackInputClosure(offset: 0)
        let stub = try Stub<any ExternalClosureStackBridgeService>()

        stub.when {
            $0.consume(any(using: directPlaceholder))
        }.then { (closure: ExternalDirectStackInputClosure) in
            externalInvokeDirectStackInput(closure)
        }
        await stub.when {
            await $0.consumeAsync(any(using: asyncPlaceholder))
        }.thenEscaping {
            (closure: ExternalDirectAsyncStackInputClosure) async in
            await externalInvokeDirectAsyncStackInput(closure)
        }

        let directInput = externalDirectStackInputClosure(offset: 100)
        #expect(
            stub().consume(directInput)
                == externalInvokeDirectStackInput(directInput)
        )
        let asyncInput = externalDirectAsyncStackInputClosure(offset: 100)
        #expect(
            await stub().consumeAsync(asyncInput)
                == externalInvokeDirectAsyncStackInput(asyncInput)
        )
    }
}

import ConsumerFixtures
import TestDoubles
import Testing

private typealias Transformer = @Sendable (Int) -> Int
private typealias AsyncTransformer = @Sendable (Int) async -> Int

@Suite struct ClosureArgumentConsumerTests {
    @Test func escapingClosureArgumentsResolveInAnOrdinaryConsumer() throws {
        let increment: Transformer = { $0 + 1 }
        let stub = try Stub<any ValueTransformer>()
        stub.when {
            $0.transform(
                Match.any(using: increment),
                value: Match.any()
            )
        }.thenEscaping { (transform: Transformer, value: Int) in
            transform(value)
        }

        let actual = stub().transform(increment, value: 41)
        #expect(actual == 42)
    }

    @Test func trailingEscapingClosureArgumentsSupportFixedOutcomes() throws {
        let increment: Transformer = { $0 + 1 }
        let stub = try Stub<any TrailingValueTransformer>()
        stub.when {
            $0.transform(
                Match.any(),
                using: Match.any(using: increment)
            )
        }.thenReturn(42)

        let actual = stub().transform(41, using: increment)
        #expect(actual == 42)
    }

    @Test func asyncEscapingClosureArgumentsResolveInAnOrdinaryConsumer() async throws {
        let increment: AsyncTransformer = { $0 + 1 }
        let stub = try Stub<any AsyncValueTransformer>()
        await stub.when {
            await $0.transform(
                Match.any(using: increment),
                value: Match.any()
            )
        }.thenEscaping { (transform: AsyncTransformer, value: Int) async in
            await transform(value)
        }

        let actual = await stub().transform(increment, value: 41)
        #expect(actual == 42)
    }

    @Test func cFunctionPointerArgumentsResolveInAnOrdinaryConsumer() throws {
        let increment: CIntTransformer = { $0 + 1 }
        let stub = try Stub<any CValueTransformer>()
        stub.when {
            $0.transform(
                Match.any(using: increment),
                value: Match.any()
            )
        }.thenEscaping { (transform: CIntTransformer, value: Int32) in
            transform(value)
        }

        let actual = stub().transform(increment, value: 41)
        #expect(actual == 42)
    }
}

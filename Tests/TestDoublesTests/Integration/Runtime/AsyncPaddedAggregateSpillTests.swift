import Testing
@testable import TestDoubles

struct AsyncPaddedTwoWordSpillValue: Equatable, Sendable {
    let word: UInt64
    let byte: UInt8
}

#if arch(x86_64) || arch(arm64)

    protocol AsyncPaddedAggregateSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncPaddedTwoWordSpillValue
        ) async -> UInt64
    }

    struct RealAsyncPaddedAggregateSpillProbe:
        AsyncPaddedAggregateSpillProbe
    {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncPaddedTwoWordSpillValue
        ) async -> UInt64 {
            await Task.yield()
            return value.word ^ UInt64(value.byte)
        }
    }

    private let asyncPaddedTwoWordSpillValue =
        AsyncPaddedTwoWordSpillValue(
            word: 0xfedc_ba98_7654_3210,
            byte: 0xa5
        )

    private func callPaddedAggregateSpill(
        _ probe: any AsyncPaddedAggregateSpillProbe
    ) async -> UInt64 {
        await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            asyncPaddedTwoWordSpillValue
        )
    }

    @Suite struct AsyncPaddedAggregateSpillTests {
        @Test func stubDecodesStoredBytesBeforeSuspension() async throws {
            #expect(MemoryLayout<AsyncPaddedTwoWordSpillValue>.size == 9)
            #expect(MemoryLayout<AsyncPaddedTwoWordSpillValue>.stride == 16)
            _ = RealAsyncPaddedAggregateSpillProbe()
            let stub = try Stub<any AsyncPaddedAggregateSpillProbe>()
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(asyncPaddedTwoWordSpillValue)
                )
            }.thenSuspend()
            let probe: any AsyncPaddedAggregateSpillProbe = stub()
            let task = Task { await callPaddedAggregateSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsStoredBytesAcrossSuspension() async throws {
            let spy = try Spy<any AsyncPaddedAggregateSpillProbe>(
                forwardingTo: RealAsyncPaddedAggregateSpillProbe()
            )

            #expect(
                await callPaddedAggregateSpill(spy())
                    == 0xfedc_ba98_7654_32b5
            )
        }
    }

#endif

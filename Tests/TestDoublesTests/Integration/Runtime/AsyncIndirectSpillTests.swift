import Testing
@testable import TestDoubles

struct AsyncIndirectSpillValue: Equatable, Sendable {
    let first: UInt64
    let second: UInt64
    let third: UInt64
    let fourth: UInt64
    let fifth: UInt64
}

#if arch(x86_64) || arch(arm64)

    protocol AsyncIndirectSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncIndirectSpillValue
        ) async -> UInt64
    }

    struct RealAsyncIndirectSpillProbe: AsyncIndirectSpillProbe {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncIndirectSpillValue
        ) async -> UInt64 {
            await Task.yield()
            return value.first ^ value.second ^ value.third
                ^ value.fourth ^ value.fifth
        }
    }

    private let asyncIndirectSpillValue = AsyncIndirectSpillValue(
        first: 0x0123_4567_89ab_cdef,
        second: 0x1020_3040_5060_7080,
        third: 0x8877_6655_4433_2211,
        fourth: 0xfedc_ba98_7654_3210,
        fifth: 0xa5a5_5a5a_c3c3_3c3c
    )

    private func indirectSpillChecksum() -> UInt64 {
        asyncIndirectSpillValue.first
            ^ asyncIndirectSpillValue.second
            ^ asyncIndirectSpillValue.third
            ^ asyncIndirectSpillValue.fourth
            ^ asyncIndirectSpillValue.fifth
    }

    private func callIndirectSpill(
        _ probe: any AsyncIndirectSpillProbe
    ) async -> UInt64 {
        await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            asyncIndirectSpillValue
        )
    }

    @Suite struct AsyncIndirectSpillTests {
        @Test func stubCopiesThePointeeBeforeSuspension() async throws {
            _ = RealAsyncIndirectSpillProbe()
            let stub = try Stub<any AsyncIndirectSpillProbe>()
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(asyncIndirectSpillValue)
                )
            }.thenSuspend()
            let probe: any AsyncIndirectSpillProbe = stub()
            let task = Task { await callIndirectSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsThePointeeAcrossSuspension() async throws {
            let spy = try Spy<any AsyncIndirectSpillProbe>(
                forwardingTo: RealAsyncIndirectSpillProbe()
            )

            #expect(await callIndirectSpill(spy()) == indirectSpillChecksum())
        }
    }

#endif

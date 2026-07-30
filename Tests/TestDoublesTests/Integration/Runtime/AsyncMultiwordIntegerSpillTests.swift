import Testing
@testable import TestDoubles

struct AsyncTwoWordSpillValue: Equatable, Sendable {
    let first: UInt64
    let second: UInt64
}

#if arch(x86_64) || arch(arm64)
    protocol AsyncMultiwordIntegerSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncTwoWordSpillValue
        ) async -> UInt64
    }

    struct RealAsyncMultiwordIntegerSpillProbe:
        AsyncMultiwordIntegerSpillProbe
    {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ value: AsyncTwoWordSpillValue
        ) async -> UInt64 {
            await Task.yield()
            return value.first ^ value.second
        }
    }

    private let asyncTwoWordSpillValue = AsyncTwoWordSpillValue(
        first: 0x0123_4567_89ab_cdef,
        second: 0xfedc_ba98_7654_3210
    )

    private func callMultiwordIntegerSpill(
        _ probe: any AsyncMultiwordIntegerSpillProbe
    ) async -> UInt64 {
        await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            asyncTwoWordSpillValue
        )
    }

    @Suite struct AsyncMultiwordIntegerSpillTests {
        @Test func stubDecodesBothWordsBeforeSuspension() async throws {
            _ = RealAsyncMultiwordIntegerSpillProbe()
            let stub = try Stub<any AsyncMultiwordIntegerSpillProbe>()
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(asyncTwoWordSpillValue)
                )
            }.thenSuspend()
            let probe: any AsyncMultiwordIntegerSpillProbe = stub()
            let task = Task { await callMultiwordIntegerSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsBothWordsAcrossSuspension() async throws {
            let spy = try Spy<any AsyncMultiwordIntegerSpillProbe>(
                forwardingTo: RealAsyncMultiwordIntegerSpillProbe()
            )

            #expect(
                await callMultiwordIntegerSpill(spy())
                    == 0xffff_ffff_ffff_ffff
            )
        }
    }

#endif

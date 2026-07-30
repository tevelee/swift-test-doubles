import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    // The leading values fill the arm64 general-purpose argument bank. On
    // x86_64 the last two also spill before the narrow integer stack slot.

    protocol AsyncPaddedIntegerSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ word: UInt32
        ) async -> UInt64
    }

    struct RealAsyncPaddedIntegerSpillProbe:
        AsyncPaddedIntegerSpillProbe
    {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ word: UInt32
        ) async -> UInt64 {
            await Task.yield()
            return UInt64(word)
        }
    }

    private func callPaddedIntegerSpill(
        _ probe: any AsyncPaddedIntegerSpillProbe
    ) async -> UInt64 {
        await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            0xcafe_babe
        )
    }

    @Suite struct AsyncPaddedIntegerSpillTests {
        @Test func stubDecodesNarrowIntegersBeforeSuspension() async throws {
            _ = RealAsyncPaddedIntegerSpillProbe()
            let stub = try Stub<any AsyncPaddedIntegerSpillProbe>()
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(UInt32(0xcafe_babe))
                )
            }.thenSuspend()
            let probe: any AsyncPaddedIntegerSpillProbe = stub()
            let task = Task { await callPaddedIntegerSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsNarrowIntegersAcrossSuspension() async throws {
            let spy = try Spy<any AsyncPaddedIntegerSpillProbe>(
                forwardingTo: RealAsyncPaddedIntegerSpillProbe()
            )

            #expect(
                await callPaddedIntegerSpill(spy())
                    == 0xcafe_babe
            )
        }
    }

#endif

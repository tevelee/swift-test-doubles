import Testing
@testable import TestDoubles

#if arch(arm64)

    // The high arity deliberately fills both argument-register banks.
    // swiftlint:disable function_parameter_count

    protocol AsyncFloat16SpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ h0: Float16, _ h1: Float16, _ h2: Float16,
            _ h3: Float16, _ h4: Float16, _ h5: Float16,
            _ h6: Float16, _ h7: Float16, _ h8: Float16
        ) async -> UInt16
    }

    struct RealAsyncFloat16SpillProbe: AsyncFloat16SpillProbe {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ h0: Float16, _ h1: Float16, _ h2: Float16,
            _ h3: Float16, _ h4: Float16, _ h5: Float16,
            _ h6: Float16, _ h7: Float16, _ h8: Float16
        ) async -> UInt16 {
            await Task.yield()
            return h8.bitPattern
        }
    }

    private let asyncFloat16SpillValues = (0 ..< 9).map {
        Float16(bitPattern: 0x3800 | UInt16($0 + 1))
    }

    private func callFloat16Spill(
        _ probe: any AsyncFloat16SpillProbe
    ) async -> UInt16 {
        let value = asyncFloat16SpillValues
        return await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            value[0], value[1], value[2],
            value[3], value[4], value[5],
            value[6], value[7], value[8]
        )
    }

    @Suite struct AsyncFloat16SpillTests {
        @Test func stubDecodesSpilledFloat16BeforeSuspension() async throws {
            _ = RealAsyncFloat16SpillProbe()
            let stub = try Stub<any AsyncFloat16SpillProbe>()
            let value = asyncFloat16SpillValues
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(value[0]), Match.equal(value[1]),
                    Match.equal(value[2]), Match.equal(value[3]),
                    Match.equal(value[4]), Match.equal(value[5]),
                    Match.equal(value[6]), Match.equal(value[7]),
                    Match.equal(value[8])
                )
            }.thenSuspend()
            let probe: any AsyncFloat16SpillProbe = stub()
            let task = Task { await callFloat16Spill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x7bcd)

            #expect(await task.value == 0x7bcd)
        }

        @Test func spyForwardsSpilledFloat16AcrossSuspension() async throws {
            let spy = try Spy<any AsyncFloat16SpillProbe>(
                forwardingTo: RealAsyncFloat16SpillProbe()
            )

            #expect(
                await callFloat16Spill(spy())
                    == asyncFloat16SpillValues[8].bitPattern
            )
        }
    }

// swiftlint:enable function_parameter_count

#endif

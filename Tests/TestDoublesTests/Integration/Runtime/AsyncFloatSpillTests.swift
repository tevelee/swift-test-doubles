import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    // The high arity deliberately fills both argument-register banks.
    // swiftlint:disable function_parameter_count

    protocol AsyncFloatSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ f0: Float, _ f1: Float, _ f2: Float,
            _ f3: Float, _ f4: Float, _ f5: Float,
            _ f6: Float, _ f7: Float, _ f8: Float
        ) async -> UInt64
    }

    struct RealAsyncFloatSpillProbe: AsyncFloatSpillProbe {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ f0: Float, _ f1: Float, _ f2: Float,
            _ f3: Float, _ f4: Float, _ f5: Float,
            _ f6: Float, _ f7: Float, _ f8: Float
        ) async -> UInt64 {
            await Task.yield()
            return floatSpillChecksum(
                integers: [a0, a1, a2, a3, a4, a5, a6, a7],
                floatingPoint: [f0, f1, f2, f3, f4, f5, f6, f7, f8]
            )
        }
    }

    private let asyncFloatSpillValues = [
        Float(bitPattern: 0x3f80_0001),
        Float(bitPattern: 0xbf80_0010),
        Float(bitPattern: 0x4000_0100),
        Float(bitPattern: 0xc000_1000),
        Float(bitPattern: 0x3f00_0001),
        Float(bitPattern: 0xbf00_0010),
        Float(bitPattern: 0x4080_0100),
        Float(bitPattern: 0xc080_1000),
        Float(bitPattern: 0x4101_0000)
    ]

    private func callFloatSpill(
        _ probe: any AsyncFloatSpillProbe
    ) async -> UInt64 {
        let value = asyncFloatSpillValues
        return await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            value[0], value[1], value[2],
            value[3], value[4], value[5],
            value[6], value[7], value[8]
        )
    }

    private func floatSpillChecksum(
        integers: [Int],
        floatingPoint: [Float]
    ) -> UInt64 {
        integers.reduce(0) { $0 &+ UInt64($1) }
            ^ floatingPoint.reduce(0) {
                $0 ^ UInt64($1.bitPattern)
            }
    }

    @Suite struct AsyncFloatSpillTests {
        @Test func stubDecodesSpilledFloatBeforeSuspension() async throws {
            _ = RealAsyncFloatSpillProbe()
            let stub = try Stub<any AsyncFloatSpillProbe>()
            let value = asyncFloatSpillValues
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
            let probe: any AsyncFloatSpillProbe = stub()
            let task = Task { await callFloatSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0xfedc_ba98_7654_3210)

            #expect(await task.value == 0xfedc_ba98_7654_3210)
        }

        @Test func spyForwardsSpilledFloatAcrossSuspension() async throws {
            let spy = try Spy<any AsyncFloatSpillProbe>(
                forwardingTo: RealAsyncFloatSpillProbe()
            )
            let expected = floatSpillChecksum(
                integers: Array(1 ... 8),
                floatingPoint: asyncFloatSpillValues
            )

            #expect(await callFloatSpill(spy()) == expected)
        }
    }

// swiftlint:enable function_parameter_count

#endif

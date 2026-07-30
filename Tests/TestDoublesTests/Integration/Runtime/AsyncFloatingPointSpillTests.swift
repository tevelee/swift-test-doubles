import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    // The high arity deliberately fills both argument-register banks.
    // swiftlint:disable function_parameter_count

    protocol AsyncFloatingPointSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ f0: Double, _ f1: Double, _ f2: Double,
            _ f3: Double, _ f4: Double, _ f5: Double,
            _ f6: Double, _ f7: Double, _ f8: Double
        ) async -> UInt64
    }

    struct RealAsyncFloatingPointSpillProbe:
        AsyncFloatingPointSpillProbe
    {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ f0: Double, _ f1: Double, _ f2: Double,
            _ f3: Double, _ f4: Double, _ f5: Double,
            _ f6: Double, _ f7: Double, _ f8: Double
        ) async -> UInt64 {
            await Task.yield()
            return floatingPointSpillChecksum(
                integers: [a0, a1, a2, a3, a4, a5, a6, a7],
                floatingPoint: [f0, f1, f2, f3, f4, f5, f6, f7, f8]
            )
        }
    }

    private let asyncFloatingPointSpillValues = [
        Double(bitPattern: 0x3ff0_0000_0000_0001),
        Double(bitPattern: 0xbff0_0000_0000_0010),
        Double(bitPattern: 0x4000_0000_0000_0100),
        Double(bitPattern: 0xc000_0000_0000_1000),
        Double(bitPattern: 0x3fe0_0000_0001_0000),
        Double(bitPattern: 0xbfe0_0000_0010_0000),
        Double(bitPattern: 0x4010_0000_0100_0000),
        Double(bitPattern: 0xc010_0000_1000_0000),
        Double(bitPattern: 0x4020_0001_0000_0000)
    ]

    private func callFloatingPointSpill(
        _ probe: any AsyncFloatingPointSpillProbe
    ) async -> UInt64 {
        let value = asyncFloatingPointSpillValues
        return await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            value[0], value[1], value[2],
            value[3], value[4], value[5],
            value[6], value[7], value[8]
        )
    }

    private func floatingPointSpillChecksum(
        integers: [Int],
        floatingPoint: [Double]
    ) -> UInt64 {
        integers.reduce(0) { $0 &+ UInt64($1) }
            ^ floatingPoint.reduce(0) { $0 ^ $1.bitPattern }
    }

    @Suite struct AsyncFloatingPointSpillTests {
        @Test func stubDecodesSpilledDoubleBeforeSuspension() async throws {
            _ = RealAsyncFloatingPointSpillProbe()
            let stub = try Stub<any AsyncFloatingPointSpillProbe>()
            let value = asyncFloatingPointSpillValues
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
            let probe: any AsyncFloatingPointSpillProbe = stub()
            let task = Task { await callFloatingPointSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x0123_4567_89ab_cdef)

            #expect(await task.value == 0x0123_4567_89ab_cdef)
        }

        @Test func spyForwardsSpilledDoubleAcrossSuspension() async throws {
            let spy = try Spy<any AsyncFloatingPointSpillProbe>(
                forwardingTo: RealAsyncFloatingPointSpillProbe()
            )
            let expected = floatingPointSpillChecksum(
                integers: Array(1 ... 8),
                floatingPoint: asyncFloatingPointSpillValues
            )

            #expect(await callFloatingPointSpill(spy()) == expected)
        }
    }

// swiftlint:enable function_parameter_count

#endif

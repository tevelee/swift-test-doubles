import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    // Four two-register values fill the vector bank; the fifth spills.
    // swiftlint:disable function_parameter_count

    protocol AsyncMultiRegisterSIMDSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ v0: SIMD8<Float>, _ v1: SIMD8<Float>,
            _ v2: SIMD8<Float>, _ v3: SIMD8<Float>,
            _ v4: SIMD8<Float>
        ) async -> UInt64
    }

    struct RealAsyncMultiRegisterSIMDSpillProbe:
        AsyncMultiRegisterSIMDSpillProbe
    {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ v0: SIMD8<Float>, _ v1: SIMD8<Float>,
            _ v2: SIMD8<Float>, _ v3: SIMD8<Float>,
            _ v4: SIMD8<Float>
        ) async -> UInt64 {
            await Task.yield()
            return multiRegisterSIMDChecksum(v4)
        }
    }

    private let asyncMultiRegisterSIMDSpillValues = (0 ..< 5).map {
        index in
        let bits = UInt32(index + 1)
        let low = SIMD4<Float>(
            Float(bitPattern: 0x3f00_0000 | bits),
            Float(bitPattern: 0x4000_0010 | bits),
            Float(bitPattern: 0xbf00_0100 | bits),
            Float(bitPattern: 0xc000_1000 | bits)
        )
        let high = SIMD4<Float>(
            Float(bitPattern: 0x3e80_0000 | bits),
            Float(bitPattern: 0x4080_0010 | bits),
            Float(bitPattern: 0xbe80_0100 | bits),
            Float(bitPattern: 0xc080_1000 | bits)
        )
        return SIMD8(lowHalf: low, highHalf: high)
    }

    private func multiRegisterSIMDChecksum(
        _ vector: SIMD8<Float>
    ) -> UInt64 {
        vector.indices.reduce(UInt64(0)) {
            $0 ^ UInt64(vector[$1].bitPattern)
        }
    }

    private func callMultiRegisterSIMDSpill(
        _ probe: any AsyncMultiRegisterSIMDSpillProbe
    ) async -> UInt64 {
        let value = asyncMultiRegisterSIMDSpillValues
        return await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            value[0], value[1], value[2], value[3], value[4]
        )
    }

    @Suite struct AsyncMultiRegisterSIMDSpillTests {
        @Test func stubDecodesEveryFragmentBeforeSuspension() async throws {
            _ = RealAsyncMultiRegisterSIMDSpillProbe()
            let stub = try Stub<any AsyncMultiRegisterSIMDSpillProbe>()
            let value = asyncMultiRegisterSIMDSpillValues
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(value[0]), Match.equal(value[1]),
                    Match.equal(value[2]), Match.equal(value[3]),
                    Match.equal(value[4])
                )
            }.thenSuspend()
            let probe: any AsyncMultiRegisterSIMDSpillProbe = stub()
            let task = Task { await callMultiRegisterSIMDSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsEveryFragmentAcrossSuspension() async throws {
            let spy = try Spy<any AsyncMultiRegisterSIMDSpillProbe>(
                forwardingTo: RealAsyncMultiRegisterSIMDSpillProbe()
            )

            #expect(
                await callMultiRegisterSIMDSpill(spy())
                    == multiRegisterSIMDChecksum(
                        asyncMultiRegisterSIMDSpillValues[4]
                    )
            )
        }
    }

// swiftlint:enable function_parameter_count

#endif

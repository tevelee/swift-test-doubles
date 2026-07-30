import Testing
@testable import TestDoubles

#if arch(x86_64) || arch(arm64)

    // The high arity fills both register banks. Three vector values spill on
    // arm64; x86_64 also spills two integers and reaches the eight-word limit.
    // swiftlint:disable function_parameter_count

    protocol AsyncSIMDSpillProbe: Sendable {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
            _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
            _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
            _ v6: SIMD4<Float>, _ v7: SIMD4<Float>,
            _ v8: SIMD4<Float>, _ v9: SIMD4<Float>,
            _ v10: SIMD4<Float>
        ) async -> UInt64
    }

    struct RealAsyncSIMDSpillProbe: AsyncSIMDSpillProbe {
        func inspect(
            _ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int,
            _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int,
            _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
            _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
            _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
            _ v6: SIMD4<Float>, _ v7: SIMD4<Float>,
            _ v8: SIMD4<Float>, _ v9: SIMD4<Float>,
            _ v10: SIMD4<Float>
        ) async -> UInt64 {
            await Task.yield()
            return simdSpillChecksum(
                integers: [a0, a1, a2, a3, a4, a5, a6, a7],
                vectors: [
                    v0, v1, v2, v3, v4, v5,
                    v6, v7, v8, v9, v10
                ]
            )
        }
    }

    private let asyncSIMDSpillValues = (0 ..< 11).map { index in
        let bits = UInt32(index + 1)
        return SIMD4<Float>(
            Float(bitPattern: 0x3f00_0000 | bits),
            Float(bitPattern: 0x4000_0010 | bits),
            Float(bitPattern: 0xbf00_0100 | bits),
            Float(bitPattern: 0xc000_1000 | bits)
        )
    }

    private func callSIMDSpill(
        _ probe: any AsyncSIMDSpillProbe
    ) async -> UInt64 {
        let value = asyncSIMDSpillValues
        return await probe.inspect(
            1, 2, 3, 4, 5, 6, 7, 8,
            value[0], value[1], value[2],
            value[3], value[4], value[5],
            value[6], value[7], value[8],
            value[9], value[10]
        )
    }

    private func simdSpillChecksum(
        integers: [Int],
        vectors: [SIMD4<Float>]
    ) -> UInt64 {
        let vectorBits = vectors.reduce(UInt64(0)) { partial, vector in
            vector.indices.reduce(partial) {
                $0 ^ UInt64(vector[$1].bitPattern)
            }
        }
        return integers.reduce(0) { $0 &+ UInt64($1) } ^ vectorBits
    }

    @Suite struct AsyncSIMDSpillTests {
        @Test func stubDecodesSpilledSIMDBeforeSuspension() async throws {
            _ = RealAsyncSIMDSpillProbe()
            let stub = try Stub<any AsyncSIMDSpillProbe>()
            let value = asyncSIMDSpillValues
            let suspension = await stub.when {
                await $0.inspect(
                    Match.any(), Match.any(), Match.any(), Match.any(),
                    Match.any(), Match.any(), Match.any(), Match.equal(8),
                    Match.equal(value[0]), Match.equal(value[1]),
                    Match.equal(value[2]), Match.equal(value[3]),
                    Match.equal(value[4]), Match.equal(value[5]),
                    Match.equal(value[6]), Match.equal(value[7]),
                    Match.equal(value[8]), Match.equal(value[9]),
                    Match.equal(value[10])
                )
            }.thenSuspend()
            let probe: any AsyncSIMDSpillProbe = stub()
            let task = Task { await callSIMDSpill(probe) }

            await suspension.waitForCall()
            suspension.resume(returning: 0x1357_9bdf_2468_ace0)

            #expect(await task.value == 0x1357_9bdf_2468_ace0)
        }

        @Test func spyForwardsSpilledSIMDAcrossSuspension() async throws {
            let spy = try Spy<any AsyncSIMDSpillProbe>(
                forwardingTo: RealAsyncSIMDSpillProbe()
            )
            let expected = simdSpillChecksum(
                integers: Array(1 ... 8),
                vectors: asyncSIMDSpillValues
            )

            #expect(await callSIMDSpill(spy()) == expected)
        }
    }

// swiftlint:enable function_parameter_count

#endif

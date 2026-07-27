import Testing
@testable import TestDoubles

protocol ConcreteSIMDABIProbe {
    func mix(
        _ vector: SIMD4<Float>,
        tag: Int,
        scale: Double,
        bits: SIMD2<UInt64>
    ) -> SIMD2<UInt64>
    func bytes(_ value: SIMD16<UInt8>) -> SIMD16<UInt8>
}

struct RealConcreteSIMDABIProbe: ConcreteSIMDABIProbe {
    func mix(
        _ vector: SIMD4<Float>,
        tag: Int,
        scale: Double,
        bits: SIMD2<UInt64>
    ) -> SIMD2<UInt64> {
        mixedSIMDResult(vector, tag: tag, scale: scale, bits: bits)
    }

    func bytes(_ value: SIMD16<UInt8>) -> SIMD16<UInt8> { value }
}

private func mixedSIMDResult(
    _ vector: SIMD4<Float>,
    tag: Int,
    scale: Double,
    bits: SIMD2<UInt64>
) -> SIMD2<UInt64> {
    let lowLanes =
        UInt64(vector[0].bitPattern)
        | UInt64(vector[1].bitPattern) << 32
    let highLanes =
        UInt64(vector[2].bitPattern)
        | UInt64(vector[3].bitPattern) << 32
    return SIMD2<UInt64>(
        bits[0] ^ lowLanes ^ UInt64(bitPattern: Int64(tag)),
        bits[1] ^ highLanes ^ scale.bitPattern
    )
}

private func makeConcreteSIMDStub() throws -> Stub<any ConcreteSIMDABIProbe> {
    try Stub<any ConcreteSIMDABIProbe>(
        .method(signatureOf: ConcreteSIMDABIProbe.mix),
        .method(signatureOf: ConcreteSIMDABIProbe.bytes)
    )
}

protocol DivergentSIMDABIProbe {
    func echo(_ value: SIMD2<Float>) -> SIMD2<Float>
}

struct RealDivergentSIMDABIProbe: DivergentSIMDABIProbe {
    func echo(_ value: SIMD2<Float>) -> SIMD2<Float> { value }
}

protocol PaddedSIMDABIProbe {
    func echo(_ value: SIMD3<Float>) -> SIMD3<Float>
}

struct RealPaddedSIMDABIProbe: PaddedSIMDABIProbe {
    func echo(_ value: SIMD3<Float>) -> SIMD3<Float> { value }
}

protocol WideSIMDABIProbe {
    func echo(_ value: SIMD8<Float>) -> SIMD8<Float>
}

struct RealWideSIMDABIProbe: WideSIMDABIProbe {
    func echo(_ value: SIMD8<Float>) -> SIMD8<Float> { value }
}

/// A result using all four vector-register return slots the trampoline
/// captures (`TrampolineCallFrame.floatingPointReturnCount`).
protocol FourRegisterReturnSIMDABIProbe {
    func widen(_ value: SIMD4<Float>) -> SIMD16<Float>
}

struct RealFourRegisterReturnSIMDABIProbe: FourRegisterReturnSIMDABIProbe {
    func widen(_ value: SIMD4<Float>) -> SIMD16<Float> {
        let half = SIMD8(lowHalf: value, highHalf: value)
        return SIMD16(lowHalf: half, highHalf: half)
    }
}

/// Wider than four vector registers: Swift itself already falls back to an
/// indirect `sret` return here (verified against compiled witness IR), so
/// this stays unsupported the same way a non-SIMD oversized aggregate does.
protocol OverflowingReturnSIMDABIProbe {
    func echo(_ value: SIMD16<Double>) -> SIMD16<Double>
}

struct RealOverflowingReturnSIMDABIProbe: OverflowingReturnSIMDABIProbe {
    func echo(_ value: SIMD16<Double>) -> SIMD16<Double> { value }
}

protocol SpilledSIMDABIProbe {
    func consume(
        _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
        _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
        _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
        _ v6: SIMD4<Float>, _ v7: SIMD4<Float>,
        _ v8: SIMD4<Float>
    )
}

struct RealSpilledSIMDABIProbe: SpilledSIMDABIProbe {
    func consume(
        _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
        _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
        _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
        _ v6: SIMD4<Float>, _ v7: SIMD4<Float>,
        _ v8: SIMD4<Float>
    ) {}
}

protocol FullVectorRegisterBankSIMDABIProbe {
    func fold(
        _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
        _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
        _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
        _ v6: SIMD4<Float>, _ v7: SIMD4<Float>
    ) -> SIMD4<UInt32>
}

struct RealFullVectorRegisterBankSIMDABIProbe:
    FullVectorRegisterBankSIMDABIProbe
{
    func fold(
        _ v0: SIMD4<Float>, _ v1: SIMD4<Float>,
        _ v2: SIMD4<Float>, _ v3: SIMD4<Float>,
        _ v4: SIMD4<Float>, _ v5: SIMD4<Float>,
        _ v6: SIMD4<Float>, _ v7: SIMD4<Float>
    ) -> SIMD4<UInt32> {
        foldedSIMDBits([v0, v1, v2, v3, v4, v5, v6, v7])
    }
}

private func foldedSIMDBits(
    _ vectors: [SIMD4<Float>]
) -> SIMD4<UInt32> {
    precondition(vectors.count == 8)
    var result = SIMD4<UInt32>(repeating: 0)
    for vector in vectors {
        for lane in 0 ..< 4 {
            result[lane] ^= vector[lane].bitPattern
        }
    }
    return result
}

private func fullWidthSIMDInput(_ index: UInt32) -> SIMD4<Float> {
    SIMD4<Float>(
        Float(bitPattern: 0x3f00_0000 | index),
        Float(bitPattern: 0x4000_0010 | index),
        Float(bitPattern: 0xbf00_0100 | index),
        Float(bitPattern: 0xc000_1000 | index)
    )
}

protocol AsyncSIMDABIProbe: Sendable {
    func echo(_ value: SIMD4<Float>) async -> SIMD4<Float>
}

struct RealAsyncSIMDABIProbe: AsyncSIMDABIProbe {
    func echo(_ value: SIMD4<Float>) async -> SIMD4<Float> { value }
}

protocol AssociatedSIMDABIProbe<Vector> {
    associatedtype Vector
    func echo(_ value: Vector) -> Vector
}

struct RealAssociatedSIMDABIProbe: AssociatedSIMDABIProbe {
    func echo(_ value: SIMD4<Float>) -> SIMD4<Float> { value }
}

struct NestedSIMDABIValue {
    let value: SIMD4<Float>
}

protocol NestedSIMDABIProbe {
    func echo(_ value: NestedSIMDABIValue) -> NestedSIMDABIValue
}

struct RealNestedSIMDABIProbe: NestedSIMDABIProbe {
    func echo(_ value: NestedSIMDABIValue) -> NestedSIMDABIValue { value }
}

@Suite struct SIMDABITests {
    @Test func mixedScalarAndVectorRegistersPreserveEveryLaneBit() throws {
        _ = RealConcreteSIMDABIProbe()
        let stub = try makeConcreteSIMDStub()
        let input = SIMD4<Float>(
            Float(bitPattern: 0x8000_0000),
            Float(bitPattern: 0x3f80_0001),
            Float(bitPattern: 0x7f7f_ffff),
            Float(bitPattern: 0xff7f_fffe)
        )
        let incomingBits = SIMD2<UInt64>(
            0x0123_4567_89ab_cdef,
            0xfedc_ba98_7654_3210
        )
        let expected = SIMD2<UInt64>(
            0x8877_6655_4433_2211,
            0x1020_3040_5060_7080
        )

        stub.when(returning: SIMD2<UInt64>(repeating: 0)) {
            $0.mix(
                any(using: SIMD4<Float>(repeating: 0)),
                tag: equal(41),
                scale: equal(2.5),
                bits: equal(incomingBits)
            )
        }.then {
            (
                vector: SIMD4<Float>, _: Int, _: Double,
                bits: SIMD2<UInt64>
            ) in
            #expect(vector[0].bitPattern == input[0].bitPattern)
            #expect(vector[1].bitPattern == input[1].bitPattern)
            #expect(vector[2].bitPattern == input[2].bitPattern)
            #expect(vector[3].bitPattern == input[3].bitPattern)
            #expect(bits == incomingBits)
            return expected
        }

        #expect(
            stub().mix(input, tag: 41, scale: 2.5, bits: incomingBits)
                == expected
        )
    }

    @Test func sixteenByteIntegerVectorRoundTripsExactly() throws {
        _ = RealConcreteSIMDABIProbe()
        let stub = try makeConcreteSIMDStub()
        let input = SIMD16<UInt8>(
            0x00, 0x11, 0x22, 0x33,
            0x44, 0x55, 0x66, 0x77,
            0x88, 0x99, 0xaa, 0xbb,
            0xcc, 0xdd, 0xee, 0xff
        )
        let expected = SIMD16<UInt8>(
            0xff, 0xee, 0xdd, 0xcc,
            0xbb, 0xaa, 0x99, 0x88,
            0x77, 0x66, 0x55, 0x44,
            0x33, 0x22, 0x11, 0x00
        )

        stub.when(returning: SIMD16<UInt8>(repeating: 0)) {
            $0.bytes(equal(input))
        }.thenReturn(expected)

        #expect(stub().bytes(input) == expected)
        stub.verify(returning: SIMD16<UInt8>(repeating: 0)) {
            $0.bytes(equal(input))
        }
    }

    @Test func smallerArchitectureDivergentVectorFailsClosed() {
        _ = RealDivergentSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "identical arm64/x86_64") {
            _ = try Stub<any DivergentSIMDABIProbe>(
                .method(signatureOf: DivergentSIMDABIProbe.echo)
            )
        }
        expectUnsupportedProtocolShape(containing: "identical arm64/x86_64") {
            _ = try Spy<any DivergentSIMDABIProbe>(
                forwardingTo: RealDivergentSIMDABIProbe()
            )
        }
    }

    @Test func paddedVectorFailsClosed() {
        _ = RealPaddedSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "complete 128-bit lane payloads") {
            _ = try Stub<any PaddedSIMDABIProbe>(
                .method(signatureOf: PaddedSIMDABIProbe.echo)
            )
        }
        expectUnsupportedProtocolShape(containing: "complete 128-bit lane payloads") {
            _ = try Spy<any PaddedSIMDABIProbe>(
                forwardingTo: RealPaddedSIMDABIProbe()
            )
        }
    }

    /// A vector wider than one 128-bit register (`SIMD8<Float>`, two
    /// registers) round-trips exactly, verified against compiled witness IR
    /// on both arm64 and x86_64 (see `concreteSIMDRegisterByteCount`).
    @Test func widerThan128BitVectorRoundTripsAcrossTwoRegisters() throws {
        _ = RealWideSIMDABIProbe()
        let input = SIMD8<Float>(1, 2, 3, 4, 5, 6, 7, 8)
        let expected = SIMD8<Float>(8, 7, 6, 5, 4, 3, 2, 1)

        let stub = try Stub<any WideSIMDABIProbe>(
            .method(signatureOf: WideSIMDABIProbe.echo)
        )
        stub.when(returning: SIMD8<Float>()) {
            $0.echo(equal(input))
        }.thenReturn(expected)
        #expect(stub().echo(input) == expected)

        let spy = try Spy<any WideSIMDABIProbe>(forwardingTo: RealWideSIMDABIProbe())
        #expect(spy().echo(input) == input)
    }

    /// A result spanning all four vector-register return slots round-trips
    /// exactly, matching the trampoline's `floatingPointReturnCount` ceiling.
    @Test func fourRegisterReturnRoundTripsAcrossAllCapturedSlots() throws {
        _ = RealFourRegisterReturnSIMDABIProbe()
        let input = SIMD4<Float>(1, 2, 3, 4)
        let half = SIMD8(lowHalf: input, highHalf: input)
        let expected = SIMD16(lowHalf: half, highHalf: half)

        let stub = try Stub<any FourRegisterReturnSIMDABIProbe>(
            .method(signatureOf: FourRegisterReturnSIMDABIProbe.widen)
        )
        stub.when(returning: SIMD16<Float>()) {
            $0.widen(equal(input))
        }.thenReturn(expected)
        #expect(stub().widen(input) == expected)

        let spy = try Spy<any FourRegisterReturnSIMDABIProbe>(
            forwardingTo: RealFourRegisterReturnSIMDABIProbe()
        )
        #expect(spy().widen(input) == expected)
    }

    /// A result wider than four vector registers still fails closed: Swift
    /// itself already returns it indirectly, matching the general oversized-
    /// aggregate boundary rather than a SIMD-specific one.
    @Test func returnWiderThanFourRegistersFailsClosed() {
        _ = RealOverflowingReturnSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "complete 128-bit lane payloads") {
            _ = try Stub<any OverflowingReturnSIMDABIProbe>(
                .method(signatureOf: OverflowingReturnSIMDABIProbe.echo)
            )
        }
        expectUnsupportedProtocolShape(containing: "complete 128-bit lane payloads") {
            _ = try Spy<any OverflowingReturnSIMDABIProbe>(
                forwardingTo: RealOverflowingReturnSIMDABIProbe()
            )
        }
    }

    @Test func ninthVectorArgumentFailsClosed() {
        _ = RealSpilledSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "spills") {
            _ = try Stub<any SpilledSIMDABIProbe>(
                .method(
                    SIMD4<Float>.self, SIMD4<Float>.self,
                    SIMD4<Float>.self, SIMD4<Float>.self,
                    SIMD4<Float>.self, SIMD4<Float>.self,
                    SIMD4<Float>.self, SIMD4<Float>.self,
                    SIMD4<Float>.self,
                    returning: Void.self
                )
            )
        }
        expectUnsupportedProtocolShape(containing: "spills") {
            _ = try Spy<any SpilledSIMDABIProbe>(
                forwardingTo: RealSpilledSIMDABIProbe()
            )
        }
    }

    @Test func asyncSIMDFailsClosed() {
        _ = RealAsyncSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "Async continuation") {
            _ = try Stub<any AsyncSIMDABIProbe>(
                .method(signatureOf: AsyncSIMDABIProbe.echo)
            )
        }
        expectUnsupportedProtocolShape(containing: "Async continuation") {
            _ = try Spy<any AsyncSIMDABIProbe>(
                forwardingTo: RealAsyncSIMDABIProbe()
            )
        }
    }

    @Test func associatedDependentSIMDFailsClosed() {
        _ = RealAssociatedSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "Associated-dependent SIMD") {
            _ = try Stub<any AssociatedSIMDABIProbe<SIMD4<Float>>>()
        }
        expectUnsupportedProtocolShape(containing: "Associated-dependent SIMD") {
            _ = try Spy<any AssociatedSIMDABIProbe<SIMD4<Float>>>(
                forwardingTo: RealAssociatedSIMDABIProbe()
            )
        }
    }

    @Test func SIMDStorageNestedInStructFailsClosedForForwarding() {
        expectUnsupportedProtocolShape(containing: "nested in an aggregate") {
            _ = try Spy<any NestedSIMDABIProbe>(
                forwardingTo: RealNestedSIMDABIProbe()
            )
        }
    }

    @Test func automaticSignatureDiscoveryResolvesConcreteSIMDArguments() throws {
        // Regression test: automatic discovery used to fail before metadata
        // resolution could reconstruct a SIMD type from its demangled name --
        // "Could not resolve runtime metadata for type 'Swift.SIMD2<Swift.Float>'"
        // -- even though the ABI-classification and calling-convention support
        // this suite proves above never had a problem with this exact shape.
        // No explicit `.method(signatureOf:)` requirements here: this is the
        // no-argument initializer that discovers everything from the
        // conformer's own witness table.
        let stub = try Stub<any ConcreteSIMDABIProbe>()
        let service: any ConcreteSIMDABIProbe = stub()
        let bits = SIMD2<UInt64>(1, 2)
        stub.when(returning: SIMD2<UInt64>(repeating: 0)) {
            $0.mix(
                any(using: SIMD4<Float>(repeating: 0)),
                tag: equal(1),
                scale: equal(1),
                bits: equal(bits)
            )
        }.thenReturn(bits)
        #expect(
            service.mix(SIMD4<Float>(repeating: 0), tag: 1, scale: 1, bits: bits)
                == bits
        )
    }

    @Test func forwardingMixedSIMDArgumentsAndResultPreserveEveryLaneBit() throws {
        let spy = try Spy<any ConcreteSIMDABIProbe>(
            forwardingTo: RealConcreteSIMDABIProbe()
        )
        let input = SIMD4<Float>(
            Float(bitPattern: 0x8000_0000),
            Float(bitPattern: 0x3f80_0001),
            Float(bitPattern: 0x7f7f_ffff),
            Float(bitPattern: 0xff7f_fffe)
        )
        let tag = 0x0123_4567
        let scale = Double(bitPattern: 0xc004_0000_0000_0001)
        let bits = SIMD2<UInt64>(
            0x0123_4567_89ab_cdef,
            0xfedc_ba98_7654_3210
        )
        let expected = mixedSIMDResult(
            input,
            tag: tag,
            scale: scale,
            bits: bits
        )

        #expect(
            spy().mix(input, tag: tag, scale: scale, bits: bits)
                == expected
        )
        spy.verify(returning: SIMD2<UInt64>(repeating: 0)) {
            $0.mix(
                equal(input),
                tag: equal(tag),
                scale: equal(scale),
                bits: equal(bits)
            )
        }
    }

    @Test func forwardingIntegerSIMDArgumentAndResultPreserveAllBytes() throws {
        let spy = try Spy<any ConcreteSIMDABIProbe>(
            forwardingTo: RealConcreteSIMDABIProbe()
        )
        let input = SIMD16<UInt8>(
            0x00, 0x11, 0x22, 0x33,
            0x44, 0x55, 0x66, 0x77,
            0x88, 0x99, 0xaa, 0xbb,
            0xcc, 0xdd, 0xee, 0xff
        )

        #expect(spy().bytes(input) == input)
        spy.verify(returning: SIMD16<UInt8>(repeating: 0)) {
            $0.bytes(equal(input))
        }
    }

    @Test func forwardingUsesAllEightVectorArgumentRegisters() throws {
        let spy = try Spy<any FullVectorRegisterBankSIMDABIProbe>(
            forwardingTo: RealFullVectorRegisterBankSIMDABIProbe()
        )
        let vectors = (0 ..< 8).map { fullWidthSIMDInput(UInt32($0 + 1)) }
        let expected = foldedSIMDBits(vectors)

        #expect(
            spy().fold(
                vectors[0], vectors[1], vectors[2], vectors[3],
                vectors[4], vectors[5], vectors[6], vectors[7]
            ) == expected
        )
        spy.verify(returning: SIMD4<UInt32>(repeating: 0)) {
            $0.fold(
                equal(vectors[0]), equal(vectors[1]),
                equal(vectors[2]), equal(vectors[3]),
                equal(vectors[4]), equal(vectors[5]),
                equal(vectors[6]), equal(vectors[7])
            )
        }
    }
}

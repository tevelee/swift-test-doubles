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
        bits
    }

    func bytes(_ value: SIMD16<UInt8>) -> SIMD16<UInt8> { value }
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

    @Test func supportedFamiliesClassifyAsOneFullVectorRegister() {
        let types: [Any.Type] = [
            SIMD4<Float>.self,
            SIMD2<Double>.self,
            SIMD2<Int>.self,
            SIMD2<UInt>.self,
            SIMD2<Int64>.self,
            SIMD2<UInt64>.self,
            SIMD4<Int32>.self,
            SIMD4<UInt32>.self,
            SIMD8<Int16>.self,
            SIMD8<UInt16>.self,
            SIMD16<Int8>.self,
            SIMD16<UInt8>.self
        ]

        for type in types {
            #expect(concreteSIMDRegisterByteCount(for: type) == 16)
            guard case .aggregate(let parts) = abiClass(for: type) else {
                Issue.record("Expected one vector-register aggregate for \(type).")
                continue
            }
            #expect(parts.count == 1)
            #expect(parts[0].register == .fp)
            #expect(parts[0].offset == 0)
            #expect(parts[0].byteCount == 16)
        }
    }

    @Test func smallerArchitectureDivergentVectorFailsClosed() {
        _ = RealDivergentSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "identical arm64/x86_64") {
            _ = try Stub<any DivergentSIMDABIProbe>(
                .method(signatureOf: DivergentSIMDABIProbe.echo)
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
    }

    @Test func vectorWiderThan128BitsFailsClosed() {
        _ = RealWideSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "complete 128-bit lane payloads") {
            _ = try Stub<any WideSIMDABIProbe>(
                .method(signatureOf: WideSIMDABIProbe.echo)
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
    }

    @Test func asyncSIMDFailsClosed() {
        _ = RealAsyncSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "Async continuation") {
            _ = try Stub<any AsyncSIMDABIProbe>(
                .method(signatureOf: AsyncSIMDABIProbe.echo)
            )
        }
    }

    @Test func associatedDependentSIMDFailsClosed() {
        _ = RealAssociatedSIMDABIProbe()
        expectUnsupportedProtocolShape(containing: "Associated-dependent SIMD") {
            _ = try Stub<any AssociatedSIMDABIProbe<SIMD4<Float>>>()
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

    @Test func forwardingSIMDFailsClosed() {
        let target: any ConcreteSIMDABIProbe = RealConcreteSIMDABIProbe()
        #expect(throws: StubError.self) {
            _ = try Spy<any ConcreteSIMDABIProbe>(forwardingTo: target)
        }
    }
}

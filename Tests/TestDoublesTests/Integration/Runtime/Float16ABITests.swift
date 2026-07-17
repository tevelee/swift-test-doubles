import Testing
@testable import TestDoubles

#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
    protocol HalfPrecisionABIProbe {
        var offset: Float16 { get }
        func scale(_ value: Float16, by factor: Float16) -> Float16
        func bounds() -> HalfPrecisionABIRange
    }

    struct HalfPrecisionABIRange: Equatable, Sendable {
        let lower: Float16
        let upper: Float16
    }

    struct RealHalfPrecisionABIProbe: HalfPrecisionABIProbe {
        var offset: Float16 { 0 }
        func scale(_ value: Float16, by factor: Float16) -> Float16 { value * factor }
        func bounds() -> HalfPrecisionABIRange {
            HalfPrecisionABIRange(lower: 0, upper: 1)
        }
    }

    @Suite struct Float16ABITests {
        @Test func float16ClassifiesAsFloatingPoint() {
            guard case .floatingPoint = abiClass(for: Float16.self, isReturn: true) else {
                Issue.record("Float16 must classify as a floating-point scalar.")
                return
            }
        }

        @Test func float16ArgumentsAndResultsRoundTrip() throws {
            let stub = try Stub<any HalfPrecisionABIProbe>()
            stub.when { $0.scale(equal(2 as Float16), by: any()) }
                .then { (value: Float16, factor: Float16) in value * factor }

            let probe = stub()
            #expect(probe.scale(2, by: 3) == 6)
            stub.verify(.exactly(1)) { $0.scale(any(), by: equal(3 as Float16)) }
        }

        @Test func float16GetterRoundTrips() throws {
            let stub = try Stub<any HalfPrecisionABIProbe>()
            stub.when { $0.offset }.thenReturn(1.5)

            #expect(stub().offset == 1.5)
        }

        @Test func aggregatesContainingFloat16RoundTrip() throws {
            let stub = try Stub<any HalfPrecisionABIProbe>()
            let expected = HalfPrecisionABIRange(lower: -1, upper: 2)
            stub.when { $0.bounds() }.thenReturn(expected)

            #expect(stub().bounds() == expected)
        }
    }
#endif

private protocol SIMDABIProbe {
    func consume(_ vector: SIMD4<Float>)
}

private protocol WrappedSIMDABIProbe {
    func measure() -> SIMDWrappingValue
}

private struct SIMDWrappingValue {
    var vector: SIMD2<Float>
}

@Suite struct SIMDRejectionTests {
    @Test func directSIMDRequirementsFailClosed() {
        expectUnsupportedProtocolShape(containing: "SIMD") {
            _ = try Stub<any SIMDABIProbe>(
                .method(SIMD4<Float>.self, returning: Void.self)
            )
        }
    }

    @Test func simdStorageNestedInStructsFailsClosed() {
        expectUnsupportedProtocolShape(containing: "SIMD") {
            _ = try Stub<any WrappedSIMDABIProbe>(
                .method(returning: SIMDWrappingValue.self)
            )
        }
    }
}

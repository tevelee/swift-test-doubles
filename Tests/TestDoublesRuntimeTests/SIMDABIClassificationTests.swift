import Testing
@testable import TestDoublesRuntime

@Suite struct SIMDABIClassificationTests {
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

    #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
        @Test func fullyPackedFloat16VectorNowClassifiesAsOneRegister() {
            #expect(
                concreteSIMDRegisterByteCount(for: SIMD8<Float16>.self) == 16
            )
        }
    #endif
}

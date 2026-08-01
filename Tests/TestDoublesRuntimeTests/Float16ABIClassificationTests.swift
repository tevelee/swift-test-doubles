import Testing
@testable import TestDoublesRuntimeMetadata

#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
    @Suite struct Float16ABIClassificationTests {
        @Test func float16ClassifiesAsFloatingPoint() {
            guard case .floatingPoint = abiClass(for: Float16.self) else {
                Issue.record("Float16 must classify as a floating-point scalar.")
                return
            }
        }
    }
#endif

@Suite struct RuntimeTypeClassificationTests {
    @Test func semanticRuntimeClassificationUsesMetadata() {
        #expect(isRuntimeFunctionType(((Int) -> Int).self))
        #expect(isRuntimeFunctionType(Int.self) == false)
        #expect(isRuntimeExistentialType((any Equatable).self))
        #expect(isRuntimeExistentialType(Int.self) == false)
    }
}

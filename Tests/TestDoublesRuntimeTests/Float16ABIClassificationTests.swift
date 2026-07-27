import Testing
@testable import TestDoublesRuntimeMetadata

#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
    @Suite struct Float16ABIClassificationTests {
        @Test func float16ClassifiesAsFloatingPoint() {
            guard case .floatingPoint = abiClass(for: Float16.self, isReturn: true) else {
                Issue.record("Float16 must classify as a floating-point scalar.")
                return
            }
        }
    }
#endif

import Testing
@testable import TestDoubles

@Suite struct UsabilityTests {

    @Test func diagnoseMissingConformance() {
        let diagnostics = RuntimeStub<any PrototypeCalculator>.diagnose()

        #expect(diagnostics.protocolName == "PrototypeCalculator")
        #expect(diagnostics.hasExistingConformance == false)
        #expect(!diagnostics.notes.isEmpty)
    }

    @Test func throwingFactorySurfacesMissingConformance() throws {
        do {
            _ = try RuntimeStub<any PrototypeCalculator>.make(strategy: .thunks)
            Issue.record("Expected missing-conformance failure")
        } catch let error as RuntimeStubError {
            switch error {
            case .noConformanceFound(let protocolName, _):
                #expect(protocolName == "PrototypeCalculator")
            default:
                Issue.record("Unexpected RuntimeStubError: \(error)")
            }
        }
    }

#if os(macOS)
    @Test func compiledSignaturesDoNotNeedRealConformer() throws {
        let stub = try RuntimeStub<any PrototypeCalculator>.compiled {
            $0.method("add", args: [.int(), .int()], returns: .int)
            $0.method("describe", args: [.int()], returns: .string)
            $0.getter("precision", type: .int)
        }

        stub.when { $0.add(1, 2) }.returns(3)
        stub.when { $0.describe(3) }.returns("3")
        stub.when { $0.precision }.returns(10)

        let sut: any PrototypeCalculator = stub()

        #expect(sut.add(1, 2) == 3)
        #expect(sut.describe(3) == "3")
        #expect(sut.precision == 10)
    }
#endif
}

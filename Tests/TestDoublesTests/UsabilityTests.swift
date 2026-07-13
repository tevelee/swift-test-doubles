#if RUNTIME_STUB
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
            _ = try RuntimeStub<any PrototypeCalculator>.make()
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

    @Test func runtimeStubRejectsAsyncRequirements() throws {
        do {
            _ = try RuntimeStub<any AsyncDataLoader>.make()
            Issue.record("Expected async requirement failure")
        } catch let error as RuntimeStubError {
            switch error {
            case .unsupportedAsyncRequirement(let protocolName, let methodName):
                #expect(protocolName == "AsyncDataLoader")
                #expect(methodName.contains("load") || methodName.contains("prefetch"))
            default:
                Issue.record("Unexpected RuntimeStubError: \(error)")
            }
        }
    }

    @Test func explicitRuntimeStubMethodsDoNotNeedRealConformer() throws {
        let stub = try RuntimeStub<any PrototypeCalculator>.make(methods: [
            .method("add(_:_:)", args: ["Int", "Int"], returns: "Int", at: 0),
            .method("describe(_:)", args: ["Int"], returns: "String", at: 1),
            .getter("precision", type: "Int", at: 2),
        ])

        stub.when { $0.add(1, 2) }.returns(3)
        stub.when { $0.describe(3) }.returns("three")
        stub.when { $0.precision }.returns(10)

        let sut: any PrototypeCalculator = stub()

        #expect(sut.add(1, 2) == 3)
        #expect(sut.describe(3) == "three")
        #expect(sut.precision == 10)
    }

    @Test func explicitRuntimeStubSlotsDoNotNeedRealConformer() throws {
        let stub = try RuntimeStub<any PrototypeCalculator>.make(
            .method(Int.self, Int.self, returns: Int.self),
            .method(Int.self, returns: String.self),
            .getter(Int.self)
        )

        stub.when { $0.add(2, 4) }.returns(6)
        stub.when { $0.describe(6) }.returns("six")
        stub.when { $0.precision }.returns(12)

        let sut: any PrototypeCalculator = stub()

        #expect(sut.add(2, 4) == 6)
        #expect(sut.describe(6) == "six")
        #expect(sut.precision == 12)
    }

    @Test func moduleSignaturesDoNotNeedRealConformer() throws {
        let stub = try RuntimeStub<any PrototypeCalculator>.makeFromModule()

        stub.when { $0.add(3, 4) }.returns(7)
        stub.when { $0.describe(7) }.returns("seven")
        stub.when { $0.precision }.returns(14)

        let sut: any PrototypeCalculator = stub()

        #expect(sut.add(3, 4) == 7)
        #expect(sut.describe(7) == "seven")
        #expect(sut.precision == 14)
    }

    @Test func moduleSignaturesResolveCustomReturnMetadata() throws {
        let stub = try RuntimeStub<any PaymentGateway>.makeFromModule()
        let expected = PaymentResult(transactionId: "tx_42", amount: 42, success: true)

        stub.when { try $0.charge(amount: any(), currency: any()) }.returns(expected)

        let sut: any PaymentGateway = stub()

        #expect(try sut.charge(amount: 42, currency: "USD") == expected)
    }

    @Test func runtimeStubDescriptionReportsRequirements() throws {
        let report = try RuntimeStub<any PrototypeCalculator>.describe()

        #expect(report.protocolName == "PrototypeCalculator")
        #expect(report.requirements.map(\.name).contains("add(_:_:)"))
        #expect(report.requirements.map(\.name).contains("describe(_:)"))
        #expect(report.requirements.map(\.name).contains("precision"))
        #expect(report.description.contains("RuntimeStub requirements for PrototypeCalculator"))
    }

    @Test func runtimeStubSetupScaffoldIsCopyPasteableShape() throws {
        let scaffold = try RuntimeStub<any PrototypeCalculator>.setupScaffold()

        #expect(scaffold.contains("let stub = try RuntimeStub<any PrototypeCalculator>.make("))
        #expect(scaffold.contains(".method(args: [Int.self, Int.self], returns: Int.self), // add(_:_:)"))
        #expect(scaffold.contains(".method(args: [Int.self], returns: String.self), // describe(_:)"))
        #expect(scaffold.contains(".getter(Int.self)"))
    }

#if COMPILED_STUB
    @Test func compiledSignaturesDoNotNeedRealConformer() throws {
        let stub = try CompiledStub<any PrototypeCalculator> {
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
#endif // COMPILED_STUB
}
#endif // RUNTIME_STUB

#if RUNTIME_STUB
import Testing
@testable import TestDoubles
import TestDoublesFixtures

private struct RuntimeAsyncError: Error, Equatable {
    let url: String
}

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

    @Test func runtimeStubSupportsAsyncRequirements() async throws {
        let stub = try RuntimeStub<any AsyncDataLoader>.make()

        await stub.when { try await $0.load(url: any()) }.returns("runtime-data")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(3)

        let sut: any AsyncDataLoader = stub()

        #expect(try await sut.load(url: "https://example.com") == "runtime-data")
        await sut.prefetch(urls: ["one", "two"])
        #expect(sut.cacheSize == 3)
        #expect(stub.calls.map(\.name).contains { $0.contains("load") })
        #expect(stub.calls.map(\.name).contains { $0.contains("prefetch") })

        await stub.verify { try await $0.load(url: any()) }.wasCalled()
        await stub.verify(called: 1) { await $0.prefetch(urls: any()) }
    }

    @Test func explicitRuntimeStubSupportsAsyncThrowingRequirements() async throws {
        let stub = try RuntimeStub<any AsyncDataLoader>.make(
            .method(String.self, returns: String.self, throws: true, async: true),
            .method([String].self, async: true),
            .getter(Int.self)
        )

        await stub.when { try await $0.load(url: equal("success")) } then: {
            "loaded"
        }
        await stub.when { try await $0.load(url: any()) } then: { args in
            throw RuntimeAsyncError(url: args[0] as! String)
        }
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(0)

        let sut: any AsyncDataLoader = stub()

        #expect(try await sut.load(url: "success") == "loaded")

        do {
            _ = try await sut.load(url: "missing")
            Issue.record("Expected the async RuntimeStub to throw")
        } catch let error as RuntimeAsyncError {
            #expect(error == RuntimeAsyncError(url: "missing"))
        }
    }

    @Test func moduleSignaturesSupportAsyncRequirements() async throws {
        let stub = try RuntimeStub<any AsyncDataLoader>.makeFromModule()

        await stub.when { try await $0.load(url: any()) }.returns("module-data")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(5)

        let sut: any AsyncDataLoader = stub()

        #expect(try await sut.load(url: "module") == "module-data")
        #expect(sut.cacheSize == 5)
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

    @Test func runtimeStubSetupScaffoldIncludesAsyncEffects() throws {
        let scaffold = try RuntimeStub<any AsyncDataLoader>.setupScaffold()

        #expect(scaffold.contains("throws: true, async: true"))
        #expect(scaffold.contains("returns: Void.self, async: true"))
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

import Testing
import Foundation
import TestDoubles
@testable import ManualStubGeneratorIntegrationFixtures

@Suite struct ManualStubGeneratorIntegrationTests {
    @Test func generatedRoutesDistinguishArgumentTypeOverloads() {
        let stub = GeneratedManualStubServiceStub()
        stub.when { $0.render(Match.equal(7)) }.thenReturn("integer")
        stub.when { $0.render(Match.equal("7")) }.thenReturn("string")

        let service: any GeneratedManualStubService = stub()
        #expect(service.render(7) == "integer")
        #expect(service.render("7") == "string")
    }

    @Test func generatedTypedThrowsPreserveTheFailureType() async throws {
        let stub = GeneratedManualStubServiceStub()
        stub.when { try $0.save(Match.equal(1)) }.thenThrow(GeneratedManualStubFailure.rejected)
        await stub.when { try await $0.refresh(Match.equal(2)) }.thenReturn("fresh")

        let service: any GeneratedManualStubService = stub()
        #expect(throws: GeneratedManualStubFailure.rejected) {
            try service.save(1)
        }
        #expect(try await service.refresh(2) == "fresh")
    }

    @Test func automaticFactoryUsesRuntimeSynthesisWhenSupported() {
        let stub = GeneratedManualStubCounterStub.automatic()
        stub.when { $0.increment(by: Match.equal(3)) }.thenDoNothing()
        stub.when { $0.value }.thenReturn(3)

        let counter: any GeneratedManualStubCounter = stub()
        counter.increment(by: 3)
        #expect(counter.value == 3)
        #expect(stub.constructionStrategy == .runtimeGenerated)
        #expect(stub.runtimeFallbackReason == nil)
    }

    @Test func automaticFactoryFallsBackForAnOpaqueImportedResult() {
        let stub = GeneratedOpaqueResultServiceStub.automatic()
        let expected = Data([2, 3, 5, 7])
        stub.when(returning: expected) { $0.load() }.thenReturn(expected)

        #expect(stub().load() == expected)
        #expect(stub.constructionStrategy == .compiledFallback)
        #expect(
            stub.runtimeFallbackReason?.description.contains("ABI-uncertain result") == true
        )
    }

    @Test func automaticFactoryUsesAGenuineActorForActorProtocols() async {
        let stub = GeneratedActorServiceStub.automatic()
        await stub.when { await $0.load(Match.equal(42)) }.thenReturn("image")

        let service: any GeneratedActorService = stub()
        #expect(await service.load(42) == "image")
        #expect(stub.constructionStrategy == .compiledFallback)
        #expect(
            stub.runtimeFallbackReason?.description.contains(
                "Actor protocols require a genuine actor instance"
            ) == true
        )
    }
}

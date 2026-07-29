import Testing
import TestDoubles
@testable import ManualStubGeneratorIntegrationFixtures

@Suite struct ManualStubGeneratorIntegrationTests {
    @Test func generatedRoutesDistinguishArgumentTypeOverloads() {
        let stub = ManualStub<GeneratedManualStubServiceManualStub>()
        stub.when { $0.render(equal(7)) }.thenReturn("integer")
        stub.when { $0.render(equal("7")) }.thenReturn("string")

        let service: any GeneratedManualStubService = stub()
        #expect(service.render(7) == "integer")
        #expect(service.render("7") == "string")
    }

    @Test func generatedTypedThrowsPreserveTheFailureType() async throws {
        let stub = ManualStub<GeneratedManualStubServiceManualStub>()
        stub.when { try $0.save(equal(1)) }.thenThrow(GeneratedManualStubFailure.rejected)
        await stub.when { try await $0.refresh(equal(2)) }.thenReturn("fresh")

        let service: any GeneratedManualStubService = stub()
        #expect(throws: GeneratedManualStubFailure.rejected) {
            try service.save(1)
        }
        #expect(try await service.refresh(2) == "fresh")
    }
}

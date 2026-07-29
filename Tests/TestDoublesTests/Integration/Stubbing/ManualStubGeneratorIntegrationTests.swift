import Testing
import TestDoubles
@testable import ManualStubGeneratorIntegrationFixtures

@Suite struct ManualStubGeneratorIntegrationTests {
    @Test func generatedRoutesDistinguishArgumentTypeOverloads() {
        let stub = ManualStub<GeneratedManualStubServiceManualStub>()
        stub.onCall { $0.render(Match.equal(7)) }.thenReturn("integer")
        stub.onCall { $0.render(Match.equal("7")) }.thenReturn("string")

        let service: any GeneratedManualStubService = stub()
        #expect(service.render(7) == "integer")
        #expect(service.render("7") == "string")
    }

    @Test func generatedTypedThrowsPreserveTheFailureType() async throws {
        let stub = ManualStub<GeneratedManualStubServiceManualStub>()
        stub.onCall { try $0.save(Match.equal(1)) }.thenThrow(GeneratedManualStubFailure.rejected)
        await stub.onCall { try await $0.refresh(Match.equal(2)) }.thenReturn("fresh")

        let service: any GeneratedManualStubService = stub()
        #expect(throws: GeneratedManualStubFailure.rejected) {
            try service.save(1)
        }
        #expect(try await service.refresh(2) == "fresh")
    }
}

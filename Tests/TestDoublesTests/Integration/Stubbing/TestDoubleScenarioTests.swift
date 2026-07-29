import TestDoubles
import Testing

private protocol RuntimeScenarioService {
    func user(id: Int) -> String
    func load(id: Int) async -> String
}

private protocol ManualScenarioServiceProtocol {
    func user(id: Int) -> String
}

private struct ManualScenarioService: ManualScenarioServiceProtocol, StubConformer {
    let stub: ManualStub<Self>

    func user(id: Int) -> String { stub.user(id: id) }
}

private func makeScenarioStub() throws -> Stub<any RuntimeScenarioService> {
    try Stub<any RuntimeScenarioService>(
        .method(Int.self, returning: String.self),
        .method(Int.self, returning: String.self, isAsync: true)
    )
}

@Suite struct TestDoubleScenarioTests {
    @Test func synchronousStubScenarioPackagesAndComposesRegistrations() throws {
        let guest: StubScenario<any RuntimeScenarioService> = .init {
            $0.onCall { $0.user(id: Match.equal(0)) }.thenReturn("Guest")
        }
        let fallback: StubScenario<any RuntimeScenarioService> = .init {
            $0.onCall { $0.user(id: Match.any()) }.thenReturn("Member")
        }
        let stub = try makeScenarioStub()

        guest.appending(fallback).apply(to: stub)

        let service: any RuntimeScenarioService = stub()
        #expect(service.user(id: 0) == "Guest")
        #expect(service.user(id: 42) == "Member")
    }

    @Test func manualStubScenarioUsesTheSameConfigurationVocabulary() {
        let scenario: ManualStubScenario<ManualScenarioService> = .init {
            $0.onCall { $0.user(id: Match.any()) }.thenReturn("Member")
        }
        let stub = ManualStub<ManualScenarioService>()

        scenario.apply(to: stub)

        let service: any ManualScenarioServiceProtocol = stub()
        #expect(service.user(id: 42) == "Member")
    }

    @Test func asyncScenarioRecordsAsyncRequirements() async throws {
        let scenario: AsyncStubScenario<any RuntimeScenarioService> = .init {
            await $0.onCall { await $0.load(id: Match.any()) }.then { (id: Int) async -> String in
                "value:\(id)"
            }
        }
        let stub = try makeScenarioStub()

        await scenario.apply(to: stub)

        let service: any RuntimeScenarioService = stub()
        #expect(await service.load(id: 42) == "value:42")
    }
}

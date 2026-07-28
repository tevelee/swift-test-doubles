import TestDoubles
import Testing

private protocol ScenarioService {
    func user(id: Int) -> String
    func load(id: Int) async -> String
}

private struct ManualScenarioService: ScenarioService, StubConformer {
    let stub: ManualStub<Self>

    func user(id: Int) -> String { stub.user(id: id) }
    func load(id: Int) async -> String { await stub.load(id: id) }
}

private func makeScenarioStub() throws -> Stub<any ScenarioService> {
    try Stub<any ScenarioService>(
        .method(Int.self, returning: String.self),
        .method(Int.self, returning: String.self, isAsync: true)
    )
}

@Suite struct TestDoubleScenarioTests {
    @Test func synchronousStubScenarioPackagesAndComposesRegistrations() throws {
        let guest: StubScenario<any ScenarioService> = .init {
            $0.when { $0.user(id: equal(0)) }.thenReturn("Guest")
        }
        let fallback: StubScenario<any ScenarioService> = .init {
            $0.when { $0.user(id: any()) }.thenReturn("Member")
        }
        let stub = try makeScenarioStub()

        guest.appending(fallback).apply(to: stub)

        let service: any ScenarioService = stub()
        #expect(service.user(id: 0) == "Guest")
        #expect(service.user(id: 42) == "Member")
    }

    @Test func manualStubScenarioUsesTheSameConfigurationVocabulary() {
        let scenario: ManualStubScenario<ManualScenarioService> = .init {
            $0.when { $0.user(id: any()) }.thenReturn("Member")
        }
        let stub = ManualStub<ManualScenarioService>()

        scenario.apply(to: stub)

        let service: any ScenarioService = stub()
        #expect(service.user(id: 42) == "Member")
    }

    @Test func asyncScenarioRecordsAsyncRequirements() async throws {
        let scenario: AsyncStubScenario<any ScenarioService> = .init {
            await $0.when { await $0.load(id: any()) }.then { (id: Int) async -> String in
                "value:\(id)"
            }
        }
        let stub = try makeScenarioStub()

        await scenario.apply(to: stub)

        let service: any ScenarioService = stub()
        #expect(await service.load(id: 42) == "value:42")
    }
}

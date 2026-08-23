import TestDoubles
import TestDoublesFixtures
import Testing

@Suite struct ActorIsolatedProtocolTests {
    @Test func customGlobalActorStubPreservesIsolation() async throws {
        let stub = try Stub<any FixturePersistingService>()
        await stub.when { await $0.store(Match.equal(7)) }.then { (value: Int) in
            FixturePersistenceActor.preconditionIsolated()
            return "stub-\(value)"
        }

        let service: any FixturePersistingService = stub()
        let result = await service.store(7)

        #expect(result == "stub-7")
        await stub.verify { await $0.store(7) }
    }

    @Test func customGlobalActorSpyPreservesIsolationWhenForwarding() async throws {
        let target = await LiveFixturePersistingService()
        let spy = try Spy<any FixturePersistingService>(forwardingTo: target)
        await spy.when { await $0.store(Match.equal(11)) }.thenForward()

        let service: any FixturePersistingService = spy()
        let result = await service.store(11)

        #expect(result == "live-11")
        await spy.verify { await $0.store(11) }
    }

    @Test func mainActorSpyPreservesIsolationForOverrides() async throws {
        let target = await LiveFixtureMainActorService()
        let spy = try Spy<any FixtureMainActorService>(forwardingTo: target)
        await spy.when { await $0.render(Match.equal(13)) }.then { (value: Int) in
            MainActor.preconditionIsolated()
            return "override-\(value)"
        }

        let service: any FixtureMainActorService = spy()
        let result = await service.render(13)

        #expect(result == "override-13")
        await spy.verify { await $0.render(13) }
    }
}

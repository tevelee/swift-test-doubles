import Testing
@testable import TestDoubles

private enum ForwardingTestError: Error, Equatable {
    case flaky
}

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol ForwardingProbeService: Sendable {
    func name(for id: Int) -> String
    func load(url: String) async throws -> String
}

struct RealForwardingProbeService: ForwardingProbeService {
    func name(for id: Int) -> String { "real-\(id)" }
    func load(url: String) async throws -> String { "live-\(url)" }
}

@Suite struct ForwardingBehaviorTests {
    @Test func chainEndsByForwardingToTheTarget() async throws {
        let spy: Spy<any ForwardingProbeService> = Spy.make(
            forwardingTo: RealForwardingProbeService()
        )
        await spy.when { try await $0.load(url: any()) }
            .thenThrow(ForwardingTestError.flaky, times: 2)
            .thenForward()

        let service: any ForwardingProbeService = spy()
        await #expect(throws: ForwardingTestError.flaky) {
            try await service.load(url: "feed")
        }
        await #expect(throws: ForwardingTestError.flaky) {
            try await service.load(url: "feed")
        }
        #expect(try await service.load(url: "feed") == "live-feed")
        #expect(try await service.load(url: "feed") == "live-feed")
    }

    @Test func standaloneForwardPunchesAHoleThroughABroaderOverride() throws {
        let spy: Spy<any ForwardingProbeService> = Spy.make(
            forwardingTo: RealForwardingProbeService()
        )
        spy.when { $0.name(for: equal(7)) }.thenForward()
        spy.when { $0.name(for: any()) }.thenReturn("stubbed")

        let service: any ForwardingProbeService = spy()
        #expect(service.name(for: 1) == "stubbed")
        #expect(service.name(for: 7) == "real-7")
    }

    @Test func syncChainEndsByForwardingToTheTarget() throws {
        let spy: Spy<any ForwardingProbeService> = Spy.make(
            forwardingTo: RealForwardingProbeService()
        )
        spy.when { $0.name(for: any()) }
            .thenReturn("once")
            .thenForward()

        let service: any ForwardingProbeService = spy()
        #expect(service.name(for: 2) == "once")
        #expect(service.name(for: 2) == "real-2")
    }

    @Test func forwardedAnswersAreRecordedForVerification() throws {
        let spy: Spy<any ForwardingProbeService> = Spy.make(
            forwardingTo: RealForwardingProbeService()
        )
        spy.when { $0.name(for: any()) }.thenForward()

        let service: any ForwardingProbeService = spy()
        _ = service.name(for: 1)
        _ = service.name(for: 2)

        spy.verify(.exactly(2)) { $0.name(for: any()) }
    }
}

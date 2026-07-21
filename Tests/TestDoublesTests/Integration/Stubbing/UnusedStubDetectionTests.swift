import IssueReporting
import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol UnusedStubProbeService: Sendable {
    func value(for id: Int) -> String
    func notify(_ value: Int)
}

struct RealUnusedStubProbeService: UnusedStubProbeService {
    func value(for id: Int) -> String { "\(id)" }
    func notify(_ value: Int) {}
}

private protocol ManualUnusedStubService {
    func value(for id: Int) -> String
}

private struct ManualUnusedStubServiceStub: ManualUnusedStubService, StubConformer {
    let stub: ManualStub<Self>

    func value(for id: Int) -> String { stub.value(for: id) }
}

@Suite struct UnusedStubDetectionTests {
    @Test func reportsRegistrationsNeverMatchedByAnyCall() throws {
        let stub = try Stub<any UnusedStubProbeService>()
        stub.when { $0.value(for: any()) }.thenReturn("used")
        stub.when { $0.notify(any()) }.thenDoNothing()

        _ = stub().value(for: 1)

        expectReportsIssue {
            stub.verifyNoUnusedStubs()
        } matching: {
            $0.description.contains("Unused stub registrations")
                && $0.description.contains("notify")
        }
    }

    @Test func passesWhenEveryRegistrationServedACall() throws {
        let stub = try Stub<any UnusedStubProbeService>()
        stub.when { $0.value(for: any()) }.thenReturn("used")
        stub.when { $0.notify(any()) }.thenDoNothing()

        let service: any UnusedStubProbeService = stub()
        _ = service.value(for: 1)
        service.notify(2)

        stub.verifyNoUnusedStubs()
    }

    @Test func reportsARegistrationShadowedByAnEarlierCatchAll() throws {
        let stub = try Stub<any UnusedStubProbeService>()
        // Registered in the wrong order: the catch-all swallows every call,
        // so the specific registration below it can never match. The shadow
        // is reported eagerly at the when site, and verifyNoUnusedStubs
        // reports it again as an unused registration at end of test.
        stub.when { $0.value(for: any()) }.thenReturn("broad")
        expectReportsIssue {
            stub.when { $0.value(for: equal(7)) }.thenReturn("specific")
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }

        #expect(stub().value(for: 7) == "broad")

        expectReportsIssue {
            stub.verifyNoUnusedStubs()
        } matching: {
            $0.description.contains("Unused stub registrations")
        }
    }

    @Test func clearingBehaviorsResetsTheTracking() throws {
        let stub = try Stub<any UnusedStubProbeService>()
        stub.when { $0.notify(any()) }.thenDoNothing()

        stub.clearConfiguredBehaviors()
        stub.when { $0.value(for: any()) }.thenReturn("used")
        _ = stub().value(for: 1)

        stub.verifyNoUnusedStubs()
    }

    @Test func manualStubReportsUnusedRegistrations() {
        let stub = ManualStub<ManualUnusedStubServiceStub>()
        stub.when { $0.value(for: equal(1)) }.thenReturn("one")
        stub.when { $0.value(for: equal(2)) }.thenReturn("two")

        let service: any ManualUnusedStubService = stub()
        _ = service.value(for: 1)

        expectReportsIssue {
            stub.verifyNoUnusedStubs()
        } matching: {
            $0.description.contains("Unused stub registrations")
        }
    }
}

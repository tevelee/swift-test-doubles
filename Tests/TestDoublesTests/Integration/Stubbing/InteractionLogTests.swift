import IssueReporting
import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol InteractionLogAnalytics {
    func track(event: String, value: Int)
    func flush()
    func fail() throws
}

struct RealInteractionLogAnalytics: InteractionLogAnalytics {
    func track(event: String, value: Int) {}
    func flush() {}
    func fail() throws {}
}

private enum InteractionLogError: Error {
    case failed
}

private protocol ManualInteractionLogService {
    func track(event: String, value: Int)
}

private struct ManualInteractionLogServiceStub: ManualInteractionLogService, ManualStubConformer {
    let stub: ManualStub<Self>

    func track(event: String, value: Int) { stub.track(event: event, value: value) }
}

@Suite struct InteractionLogTests {
    @Test func describesRecordedCallsInOrderWithWovenLabels() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()
        stub.when { $0.flush() }.thenDoNothing()

        let analytics: any InteractionLogAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)
        analytics.flush()

        #expect(
            stub.describeInteractions() == """
                [TestDoubles] Recorded 3 interactions in order:
                  #1  track(event: "add_to_cart", value: 30)
                  #2  track(event: "purchase", value: 42)
                  #3  flush()
                """
        )
    }

    @Test func reportsWhenNothingWasRecorded() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        #expect(stub.describeInteractions() == "[TestDoubles] No interactions recorded.")
    }

    @Test func numberColumnAlignsAcrossOrdersOfMagnitude() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        stub.when { $0.flush() }.thenDoNothing()

        let analytics: any InteractionLogAnalytics = stub()
        for _ in 0 ..< 10 { analytics.flush() }

        let lines = stub.describeInteractions().split(separator: "\n").map(String.init)
        #expect(lines.count == 11)
        // The single-digit rows are right-aligned under the two-digit row.
        #expect(lines[1] == "   #1  flush()")
        #expect(lines[10] == "  #10  flush()")
    }

    @Test func describingIsAQueryThatDoesNotConsumeBehaviorOrVerification() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()

        let analytics: any InteractionLogAnalytics = stub()
        analytics.track(event: "purchase", value: 42)

        _ = stub.describeInteractions()

        // A verification still sees the call describeInteractions read.
        stub.verify(.exactly(1)) { $0.track(event: Match.equal("purchase"), value: Match.equal(42)) }
    }

    @Test func manualStubDescribesRecordedCalls() {
        let stub = ManualStub<ManualInteractionLogServiceStub>()
        stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()

        let service: any ManualInteractionLogService = stub()
        service.track(event: "add_to_cart", value: 30)

        #expect(
            stub.describeInteractions() == """
                [TestDoubles] Recorded 1 interaction in order:
                  #1  track(event: "add_to_cart", value: 30)
                """
        )
    }

    @Test func wholeDoubleHistoryComposesCountsDispatchAndTimeline() throws {
        let spy: Spy<any InteractionLogAnalytics> = Spy.make(
            forwardingTo: RealInteractionLogAnalytics()
        )
        spy.when {
            $0.track(event: Match.any(), value: Match.any())
        }.thenDoNothing()

        let analytics: any InteractionLogAnalytics = spy()
        analytics.track(event: "purchase", value: 42)
        analytics.flush()

        #expect(spy.history.callCount == 2)
        #expect(spy.history.wasCalled)
        #expect(spy.history.stubbed.callCount == 1)
        #expect(spy.history.forwarded.callCount == 1)
        #expect(spy.history.timeline.events.map(\.dispatch.rawValue) == ["stubbed", "forwarded"])
        #expect(spy.history.description == spy.describeInteractions())

        spy.history.stubbed.verify()
        spy.history.forwarded.verify()
        spy.history.verifyNoMoreInteractions()
    }

    @Test func wholeDoubleHistoryReportsRangeMismatches() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        stub.when { $0.flush() }.thenDoNothing()
        stub().flush()

        expectReportsIssue {
            stub.history.verify(2 ... 3)
        } matching: {
            $0.description.contains("Interaction history")
                && $0.description.contains("between 2 calls and 3 calls")
                && $0.description.contains("got 1")
        }
    }

    @Test func wholeDoubleHistoryIsAStableCollectionSnapshot() throws {
        let stub = try Stub<any InteractionLogAnalytics>()
        stub.when { $0.flush() }.thenDoNothing()
        stub.when { try $0.fail() }.thenThrow(InteractionLogError.failed)

        let analytics: any InteractionLogAnalytics = stub()
        analytics.flush()
        let snapshot = stub.history
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.outcome == .returned)
        #expect(snapshot.first?.didThrow == false)

        #expect(throws: InteractionLogError.self) { try analytics.fail() }

        #expect(snapshot.count == 1)
        #expect(stub.history.count == 2)
        #expect(stub.history.filter(\.didThrow).map(\.requirement) == ["fail()"])
    }
}

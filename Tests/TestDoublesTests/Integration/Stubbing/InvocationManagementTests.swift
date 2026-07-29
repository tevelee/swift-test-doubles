import Foundation
import IssueReporting
import TestDoubles
import Testing

protocol InvocationManagementService: Sendable {
    func value(for id: Int) -> String
    func notify(_ value: Int)
    func next() -> Int
}

struct RealInvocationManagementService: InvocationManagementService {
    func value(for id: Int) -> String { "\(id)" }
    func notify(_ value: Int) {}
    func next() -> Int { 0 }
}

private protocol ManualInvocationManagementService {
    func value(for id: Int) -> String
    func reset()
}

private struct ManualInvocationManagementServiceStub: ManualInvocationManagementService,
    StubConformer
{
    let stub: ManualStub<Self>

    func value(for id: Int) -> String { stub.value(for: id) }
    func reset() { stub.reset() }
}

private final class BlockedBehaviorMatcherGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var matcherEntered = false
    private var matcherReleased = false

    func matchAfterRelease(_ value: Int) -> Bool {
        condition.lock()
        matcherEntered = true
        condition.broadcast()
        while matcherReleased == false {
            condition.wait()
        }
        condition.unlock()
        return value == 7
    }

    func waitUntilMatcherEntered(within timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while matcherEntered == false {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    func releaseMatcher() {
        condition.lock()
        matcherReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private actor MatcherEvaluationGate {
    private var evaluationCount = 0

    func recordEvaluation() {
        evaluationCount += 1
    }

    func waitUntilEvaluated(
        atLeast expectedCount: Int,
        within timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while evaluationCount < expectedCount {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}

@Suite struct InvocationManagementTests {
    @Test func stubClearingBehaviorsRemovesShadowingRegistrations() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("old")
        let service: any InvocationManagementService = stub()
        #expect(service.value(for: 1) == "old")

        stub.clearConfiguredBehaviors()

        // Without the clear, first-match-wins would keep answering "old".
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("new")
        #expect(service.value(for: 2) == "new")

        // Clearing behaviors preserves the invocation log.
        stub.verify(.exactly(2)) { $0.value(for: Match.any()) }
    }

    @Test func stubResetRestoresJustConstructedState() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("old")
        let service: any InvocationManagementService = stub()
        #expect(service.value(for: 1) == "old")

        stub.reset()

        stub.verify(.never) { $0.value(for: Match.any()) }
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("new")
        #expect(service.value(for: 2) == "new")
        stub.verify(.exactly(1)) { $0.value(for: Match.any()) }
    }

    @Test func spyClearingBehaviorsRestoresForwarding() throws {
        let spy: Spy<any InvocationManagementService> = Spy.make(
            forwardingTo: RealInvocationManagementService()
        )
        spy.onCall { $0.value(for: Match.any()) }.thenReturn("stubbed")
        let service: any InvocationManagementService = spy()
        #expect(service.value(for: 7) == "stubbed")

        spy.clearConfiguredBehaviors()

        #expect(service.value(for: 7) == "7")
    }

    @Test(.timeLimit(.minutes(2)))
    func clearingWhileMatcherIsBlockedCannotDispatchRemovedBehavior() async throws {
        let spy: Spy<any InvocationManagementService> = Spy.make(
            forwardingTo: RealInvocationManagementService()
        )
        let gate = BlockedBehaviorMatcherGate()
        spy.onCall {
            $0.value(
                for: Match.matching(
                    description: "blocked",
                    where: gate.matchAfterRelease
                )
            )
        }.thenReturn("stale")
        let service: any InvocationManagementService = spy()

        let invocation = Task.detached {
            service.value(for: 7)
        }
        guard gate.waitUntilMatcherEntered(within: 60) else {
            gate.releaseMatcher()
            invocation.cancel()
            _ = await invocation.value
            Issue.record("The blocking matcher did not start within 60 seconds.")
            return
        }
        spy.clearConfiguredBehaviors()
        gate.releaseMatcher()

        #expect(await invocation.value == "7")
    }

    @Test func manualStubClearingBehaviorsRemovesShadowingRegistrations() {
        let stub = ManualStub<ManualInvocationManagementServiceStub>()
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("old")
        let service: any ManualInvocationManagementService = stub()
        #expect(service.value(for: 1) == "old")

        stub.clearConfiguredBehaviors()

        stub.onCall { $0.value(for: Match.any()) }.thenReturn("new")
        #expect(service.value(for: 2) == "new")
        stub.verify(.exactly(2)) { $0.value(for: Match.any()) }
    }

    @Test func stubClearsOldCallsButPreservesBehaviorAndRecordsNewCalls() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("configured")
        let service: any InvocationManagementService = stub()

        #expect(service.value(for: 1) == "configured")
        stub.verify(.exactly(1)) { $0.value(for: Match.any()) }

        stub.clearRecordedInvocations()

        stub.verify(.never) { $0.value(for: Match.any()) }
        expectReportsIssue {
            stub.verify { $0.value(for: Match.equal(1)) }
        } matching: {
            $0.description.contains("expected at least 1 call, got 0")
        }

        #expect(service.value(for: 2) == "configured")
        stub.verify(.exactly(1)) { $0.value(for: Match.equal(2)) }
        stub.verify(.exactly(1)) { $0.value(for: Match.any()) }
    }

    @Test func manualStubHasClearingParityWithoutInterceptingReset() {
        let stub = ManualStub<ManualInvocationManagementServiceStub>()
        stub.onCall { $0.value(for: Match.any()) }.thenReturn("configured")
        stub.onCall { $0.reset() }.thenDoNothing()
        let service: any ManualInvocationManagementService = stub()

        #expect(service.value(for: 1) == "configured")
        service.reset()
        stub.verify(.exactly(1)) { $0.value(for: Match.any()) }
        stub.verify(.exactly(1)) { $0.reset() }

        stub.clearRecordedInvocations()

        stub.verify(.never) { $0.value(for: Match.any()) }
        stub.verify(.never) { $0.reset() }
        #expect(service.value(for: 2) == "configured")
        service.reset()
        stub.verify(.exactly(1)) { $0.value(for: Match.equal(2)) }
        stub.verify(.exactly(1)) { $0.reset() }
    }

    @Test func clearingDoesNotResetReturnSequenceCursor() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.onCall { $0.next() }.thenReturn(1, 2, 3)
        let service: any InvocationManagementService = stub()

        #expect(service.next() == 1)
        stub.clearRecordedInvocations()

        #expect(service.next() == 2)
        stub.verify(.exactly(1)) { $0.next() }
    }

    @MainActor
    @Test(.timeLimit(.minutes(2)))
    func eventualVerificationReevaluatesAcrossClear() async throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.onCall { $0.notify(Match.any()) }.thenDoNothing()
        let service: any InvocationManagementService = stub()
        let completions = LockedCounter()
        let evaluationGate = MatcherEvaluationGate()

        service.notify(1)
        let verification = Task { @MainActor in
            await stub.verify(2..., within: .seconds(60)) {
                $0.notify(
                    Match.matching(description: "verification evaluation") { (value: Int) in
                        Task { await evaluationGate.recordEvaluation() }
                        return value > 0
                    }
                )
            }
            completions.increment()
        }

        guard await evaluationGate.waitUntilEvaluated(atLeast: 1, within: .seconds(60)) else {
            verification.cancel()
            await verification.value
            Issue.record("The eventual verification did not evaluate the initial call within 60 seconds.")
            return
        }
        stub.clearRecordedInvocations()
        service.notify(2)

        guard await evaluationGate.waitUntilEvaluated(atLeast: 2, within: .seconds(60)) else {
            verification.cancel()
            await verification.value
            Issue.record("The eventual verification did not re-evaluate after clearing calls within 60 seconds.")
            return
        }
        #expect(completions.value == 0)

        service.notify(3)
        await verification.value
        #expect(completions.value == 1)
        stub.verify(.exactly(2)) { $0.notify(Match.any()) }
    }
}

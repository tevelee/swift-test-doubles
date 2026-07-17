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

@Suite struct InvocationManagementTests {
    @Test func stubClearsOldCallsButPreservesBehaviorAndRecordsNewCalls() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.when { $0.value(for: any()) }.thenReturn("configured")
        let service: any InvocationManagementService = stub(sendability: .unchecked)

        #expect(service.value(for: 1) == "configured")
        stub.verify(.exactly(1)) { $0.value(for: any()) }

        stub.clearRecordedInvocations()

        stub.verify(.never()) { $0.value(for: any()) }
        expectReportsIssue {
            stub.verify { $0.value(for: equal(1)) }
        } matching: {
            $0.description.contains("expected at least 1 call, got 0")
        }

        #expect(service.value(for: 2) == "configured")
        stub.verify(.exactly(1)) { $0.value(for: equal(2)) }
        stub.verify(.exactly(1)) { $0.value(for: any()) }
    }

    @Test func manualStubHasClearingParityWithoutInterceptingReset() {
        let stub = ManualStub<ManualInvocationManagementServiceStub>()
        stub.when { $0.value(for: any()) }.thenReturn("configured")
        stub.when { $0.reset() }
        let service: any ManualInvocationManagementService = stub()

        #expect(service.value(for: 1) == "configured")
        service.reset()
        stub.verify(.exactly(1)) { $0.value(for: any()) }
        stub.verify(.exactly(1)) { $0.reset() }

        stub.clearRecordedInvocations()

        stub.verify(.never()) { $0.value(for: any()) }
        stub.verify(.never()) { $0.reset() }
        #expect(service.value(for: 2) == "configured")
        service.reset()
        stub.verify(.exactly(1)) { $0.value(for: equal(2)) }
        stub.verify(.exactly(1)) { $0.reset() }
    }

    @Test func clearingDoesNotResetReturnSequenceCursor() throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.when { $0.next() }.thenReturn(1, 2, 3)
        let service: any InvocationManagementService = stub(sendability: .unchecked)

        #expect(service.next() == 1)
        stub.clearRecordedInvocations()

        #expect(service.next() == 2)
        stub.verify(.exactly(1)) { $0.next() }
    }

    @MainActor
    @Test func eventualVerificationReevaluatesAcrossClear() async throws {
        let stub = try Stub<any InvocationManagementService>()
        stub.when { $0.notify(any()) }
        let service: any InvocationManagementService = stub(sendability: .unchecked)
        let completions = LockedCounter()

        service.notify(1)
        let verification = Task { @MainActor in
            await stub.verify(2..., within: .seconds(10)) { $0.notify(any()) }
            completions.increment()
        }

        try await Task.sleep(for: .milliseconds(10))
        stub.clearRecordedInvocations()
        service.notify(2)
        try await Task.sleep(for: .milliseconds(10))
        #expect(completions.value == 0)

        service.notify(3)
        await verification.value
        #expect(completions.value == 1)
        stub.verify(.exactly(2)) { $0.notify(any()) }
    }
}

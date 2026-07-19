import IssueReporting
import TestDoubles
import Testing

protocol NoMoreInteractionsService: Sendable {
    func first(_ value: Int) -> Int
    func second(_ value: Int) -> Int
}

struct RealNoMoreInteractionsService: NoMoreInteractionsService {
    func first(_ value: Int) -> Int { value }
    func second(_ value: Int) -> Int { value }
}

private protocol ManualNoMoreInteractionsService {
    func first(_ value: Int) -> Int
    func second(_ value: Int) -> Int
}

private struct ManualNoMoreInteractionsServiceStub: ManualNoMoreInteractionsService,
    StubConformer
{
    let stub: ManualStub<Self>

    func first(_ value: Int) -> Int { stub.first(value) }
    func second(_ value: Int) -> Int { stub.second(value) }
}

@Suite struct NoMoreInteractionsTests {
    @Test func ordinaryVerificationMarksOnlyItsMatchingSnapshot() throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        stub.when { $0.second(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)

        _ = service.first(1)
        _ = service.second(2)
        stub.verify { $0.first(equal(1)) }
        stub.verify { $0.first(equal(1)) }

        let expectedLine = UInt(#line + 2)
        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: { issue in
            issue.description.contains("found 1 unverified interaction")
                && issue.description.contains("1/1: second")
                && issue.description.contains("2")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }
    }

    @Test func manualStubHasVerificationAndClearingParity() {
        let stub = ManualStub<ManualNoMoreInteractionsServiceStub>()
        stub.when { $0.first(any()) }.thenReturn(0)
        stub.when { $0.second(any()) }.thenReturn(0)
        let service: any ManualNoMoreInteractionsService = stub()

        _ = service.first(1)
        stub.verify { $0.first(equal(1)) }
        stub.verifyNoMoreInteractions()

        _ = service.second(2)
        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: {
            $0.description.contains("second")
        }

        stub.clearRecordedInvocations()
        stub.verifyNoMoreInteractions()
    }

    @Test func orderedVerificationMarksOnlyTheDistinctSelectedCalls() throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        stub.when { $0.second(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)

        _ = service.first(1)
        _ = service.second(99)
        _ = service.first(2)

        stub.verifyInOrder {
            _ = $0.first(equal(1))
            _ = $0.first(equal(2))
        }

        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: { issue in
            issue.description.contains("found 1 unverified interaction")
                && issue.description.contains("second")
                && issue.description.contains("99")
        }
    }

    @Test func failedExactVerificationLeavesInteractionAndCaptorUntouched() throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)
        let values = ArgumentCaptor<Int>()

        _ = service.first(7)
        expectReportsIssue {
            stub.verify(.exactly(2)) { $0.first(values.capture()) }
        } matching: {
            $0.description.contains("expected 2 calls, got 1")
        }
        #expect(values.values.isEmpty)

        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: { issue in
            issue.description.contains("first")
                && issue.description.contains("7")
        }
    }

    @Test func failedOrderedVerificationLeavesInteractionAndCaptorUntouched() throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        stub.when { $0.second(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)
        let values = ArgumentCaptor<Int>()

        _ = service.first(7)
        expectReportsIssue {
            stub.verifyInOrder {
                _ = $0.first(values.capture())
                _ = $0.second(any())
            }
        } matching: {
            $0.description.contains("expectation 2")
        }
        #expect(values.values.isEmpty)

        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: { issue in
            issue.description.contains("first")
                && issue.description.contains("7")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func eventualVerificationMarksItsSnapshotButNotLaterCalls() async throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        stub.when { $0.second(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            _ = service.first(3)
        }
        await stub.verify(within: .seconds(60)) { $0.first(equal(3)) }
        try await invocation.value
        stub.verifyNoMoreInteractions()

        _ = service.second(4)
        expectReportsIssue {
            stub.verifyNoMoreInteractions()
        } matching: { issue in
            issue.description.contains("second")
                && issue.description.contains("4")
        }
    }

    @Test func clearRemovesUnverifiedInteractionsAndTheirLedgerState() throws {
        let stub = try Stub<any NoMoreInteractionsService>()
        stub.when { $0.first(any()) }.thenReturn(0)
        let service: any NoMoreInteractionsService = stub(sendability: .unchecked)

        _ = service.first(1)
        stub.clearRecordedInvocations()
        stub.verifyNoMoreInteractions()

        _ = service.first(2)
        stub.verify { $0.first(equal(2)) }
        stub.verifyNoMoreInteractions()
    }
}

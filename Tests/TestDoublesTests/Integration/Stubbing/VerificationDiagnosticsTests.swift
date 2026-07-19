import IssueReporting
import Testing
import TestDoubles

private protocol VerificationDiagnosticsProbe {
    func synchronous(_ value: Int)
    func asynchronous(_ value: Int) async
}

private func makeVerificationDiagnosticsStub() throws -> Stub<any VerificationDiagnosticsProbe> {
    try Stub<any VerificationDiagnosticsProbe>(
        .method(Int.self, returning: Void.self),
        .method(Int.self, returning: Void.self, isAsync: true)
    )
}

@Suite struct VerificationDiagnosticsTests {
    @Test func synchronousMismatchReportsAtTheCallSite() throws {
        let stub = try makeVerificationDiagnosticsStub()
        let expectedLine = UInt(#line + 2)
        expectReportsIssue {
            stub.verify { $0.synchronous(any()) }
        } matching: { issue in
            issue.description.contains("expected at least 1 call, got 0")
                && String(describing: issue.fileID) == String(describing: #fileID)
                && String(describing: issue.filePath) == String(describing: #filePath)
                && issue.line == expectedLine
                && issue.column > 0
        }
    }

    @Test func exactMismatchReportsWithoutTerminating() throws {
        let stub = try makeVerificationDiagnosticsStub()
        stub.when { $0.synchronous(any()) }.thenDoNothing()
        stub().synchronous(1)

        expectReportsIssue {
            stub.verify(.exactly(2)) { $0.synchronous(any()) }
        } matching: {
            $0.description.contains("expected 2 calls, got 1")
        }
    }

    @Test func asynchronousMismatchReportsWithoutTerminating() async throws {
        let stub = try makeVerificationDiagnosticsStub()
        await stub.when { await $0.asynchronous(any()) }.thenDoNothing()
        await stub().asynchronous(1)

        await expectReportsIssue {
            await stub.verify(.never()) { await $0.asynchronous(any()) }
        } matching: {
            $0.description.contains("expected no calls, got 1")
        }
    }

    @Test func upperBoundMismatchReportsWithoutTerminating() throws {
        let stub = try makeVerificationDiagnosticsStub()
        stub.when { $0.synchronous(any()) }.thenDoNothing()
        stub().synchronous(1)

        expectReportsIssue {
            stub.verify(...0) { $0.synchronous(any()) }
        } matching: {
            $0.description.contains("expected at most 0 calls, got 1")
        }
    }

    @Test func successfulSynchronousVerificationReportsNothing() throws {
        let stub = try makeVerificationDiagnosticsStub()
        stub.when { $0.synchronous(any()) }.thenDoNothing()
        stub().synchronous(1)

        expectReportsIssue {
            stub.verify(.exactly(1)) { $0.synchronous(any()) }
            reportIssue("successful-synchronous-verification")
        } matching: {
            $0.description.contains("successful-synchronous-verification")
        }
    }

    @Test func successfulAsynchronousVerificationReportsNothing() async throws {
        let stub = try makeVerificationDiagnosticsStub()
        await stub.when { await $0.asynchronous(any()) }.thenDoNothing()
        await stub().asynchronous(1)

        await expectReportsIssue {
            await stub.verify(.exactly(1)) { await $0.asynchronous(any()) }
            reportIssue("successful-asynchronous-verification")
        } matching: {
            $0.description.contains("successful-asynchronous-verification")
        }
    }
}

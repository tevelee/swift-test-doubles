import Foundation
import IssueReporting

struct ReportedIssue: Sendable {
    let description: String
    let severity: IssueSeverity
    let fileID: StaticString
    let filePath: StaticString
    let line: UInt
    let column: UInt
}

private final class CapturingIssueReporter: IssueReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ReportedIssue] = []

    var issues: [ReportedIssue] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        let message = message() ?? ""
        lock.lock()
        storage.append(
            ReportedIssue(
                description:
                    "Issue reported\(message.isEmpty ? "" : ": \(message)")",
                severity: severity,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        )
        lock.unlock()
    }
}

func expectReportsIssue(
    _ message: @autoclosure () -> String? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ body: () throws -> Void,
    matching issueMatcher: (ReportedIssue) -> Bool
) rethrows {
    let reporter = CapturingIssueReporter()
    try withIssueReporters([reporter], operation: body)
    validateCapturedIssues(
        reporter.issues,
        message: message(),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        matching: issueMatcher
    )
}

func expectReportsIssue(
    _ message: @autoclosure () -> String? = nil,
    isolation: isolated (any Actor)? = #isolation,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    _ body: () async throws -> Void,
    matching issueMatcher: (ReportedIssue) -> Bool
) async rethrows {
    let reporter = CapturingIssueReporter()
    try await withIssueReporters(
        [reporter],
        isolation: isolation,
        operation: body
    )
    validateCapturedIssues(
        reporter.issues,
        message: message(),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        matching: issueMatcher
    )
}

private func validateCapturedIssues(
    _ issues: [ReportedIssue],
    message: String?,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt,
    matching issueMatcher: (ReportedIssue) -> Bool
) {
    guard !issues.isEmpty else {
        reportIssue(
            "Expected issue to be reported\(message.map { ": \($0)" } ?? "")",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return
    }
    for issue in issues where !issueMatcher(issue) {
        reportIssue(
            "Issue does not match: \(issue.description)",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

import Foundation

/// A type-erased resource check owned by a test-double test scope.
///
/// The closure form keeps generic resource controls such as `CallbackCapture`
/// independent from the session's storage.
final class TestDoubleTeardownCheck: @unchecked Sendable {
    enum Kind: Hashable {
        case behaviorQueue
        case suspension
        case callbackCapture
        case testDoubleLifetime
        case invocationStream
        case streamController
    }

    let kind: Kind
    private let diagnostic: () -> String?

    init(kind: Kind, diagnostic: @escaping () -> String?) {
        self.kind = kind
        self.diagnostic = diagnostic
    }

    func makeDiagnostic() -> String? {
        diagnostic()
    }
}

/// A lazily rendered fixture comparison owned by a test scope.
final class TestDoubleFixtureDiffCheck: @unchecked Sendable {
    let name: String
    private let difference: () -> String?

    init(name: String, difference: @escaping () -> String?) {
        self.name = name
        self.difference = difference
    }

    func makeDifference() -> String? {
        difference()
    }
}

/// A text artifact that `TestDoublesTesting` records with Swift Testing.
@_spi(Testing) public struct TestDoubleFailureAttachment: Sendable {
    /// The preferred attachment filename.
    @_spi(Testing) public let name: String

    /// The UTF-8 text stored in the attachment.
    @_spi(Testing) public let contents: String
}

/// Per-test state used by the opt-in `TestDoublesTesting` product.
///
/// This SPI keeps Swift Testing out of the main `TestDoubles` product, which
/// continues to support the package's complete deployment range.
@_spi(Testing) public final class TestDoubleSession: @unchecked Sendable {
    private let lock = NSLock()
    private var recorders: [StubRecorder] = []
    private var teardownChecks: [TestDoubleTeardownCheck] = []
    private var fixtureDiffChecks: [TestDoubleFixtureDiffCheck] = []
    private let automaticNamePrefix: String?
    private var nextAutomaticNameOrdinal = 1

    /// Creates an empty test-double session.
    @_spi(Testing) public init() {
        automaticNamePrefix = nil
    }

    /// Creates a session that assigns stable, scope-local names to unnamed doubles.
    @_spi(Testing) public init(automaticNamePrefix: String) {
        self.automaticNamePrefix = automaticNamePrefix
    }

    func register(_ recorder: StubRecorder) {
        lock.lock()
        guard recorders.contains(where: { $0 === recorder }) == false else {
            lock.unlock()
            return
        }
        recorders.append(recorder)
        let automaticName = automaticNamePrefix.map {
            defer { nextAutomaticNameOrdinal += 1 }
            return "\($0) double \(nextAutomaticNameOrdinal)"
        }
        lock.unlock()
        if let automaticName {
            recorder.nameTestDoubleIfUnnamed(automaticName)
        }
    }

    func register(_ teardownCheck: TestDoubleTeardownCheck) {
        lock.lock()
        defer { lock.unlock() }
        teardownChecks.append(teardownCheck)
    }

    func registerLifetime(
        of recorder: StubRecorder,
        isAlive: @escaping () -> Bool
    ) {
        register(
            TestDoubleTeardownCheck(kind: .testDoubleLifetime) {
                guard isAlive() else { return nil }
                let label = recorder.testDoubleName.map { " '\($0)'" } ?? ""
                return "Test double\(label) outlived its test scope. "
                    + "Release generated values, injected closures, and controller references "
                    + "before the scoped test returns."
            }
        )
    }

    func registerFixtureDiff(
        named name: String,
        difference: @escaping () -> String?
    ) {
        lock.lock()
        defer { lock.unlock() }
        fixtureDiffChecks.append(
            TestDoubleFixtureDiffCheck(name: name, difference: difference)
        )
    }

    /// Returns diagnostics for the requested automatic teardown checks.
    @_spi(Testing) public func diagnostics(
        checkingUnusedRegistrations: Bool,
        checkingUnverifiedInteractions: Bool,
        checkingUnconsumedBehaviorQueues: Bool = false,
        checkingPendingSuspensions: Bool = false,
        checkingPendingCallbackCaptures: Bool = false,
        checkingEscapedTestDoubles: Bool = false,
        checkingUnfinishedAsyncInvocations: Bool = false,
        checkingUnconsumedInvocationStreams: Bool = false,
        checkingOpenStreamControllers: Bool = false
    ) -> [String] {
        issues(
            checkingUnusedRegistrations: checkingUnusedRegistrations,
            checkingUnverifiedInteractions: checkingUnverifiedInteractions,
            checkingUnconsumedBehaviorQueues: checkingUnconsumedBehaviorQueues,
            checkingPendingSuspensions: checkingPendingSuspensions,
            checkingPendingCallbackCaptures: checkingPendingCallbackCaptures,
            checkingEscapedTestDoubles: checkingEscapedTestDoubles,
            checkingUnfinishedAsyncInvocations: checkingUnfinishedAsyncInvocations,
            checkingUnconsumedInvocationStreams: checkingUnconsumedInvocationStreams,
            checkingOpenStreamControllers: checkingOpenStreamControllers
        ).map(\.description)
    }

    /// Returns structured issues for the requested automatic teardown checks.
    @_spi(Testing) public func issues(
        checkingUnusedRegistrations: Bool,
        checkingUnverifiedInteractions: Bool,
        checkingUnconsumedBehaviorQueues: Bool = false,
        checkingPendingSuspensions: Bool = false,
        checkingPendingCallbackCaptures: Bool = false,
        checkingEscapedTestDoubles: Bool = false,
        checkingUnfinishedAsyncInvocations: Bool = false,
        checkingUnconsumedInvocationStreams: Bool = false,
        checkingOpenStreamControllers: Bool = false
    ) -> [TestDoubleIssue] {
        let (recorders, teardownChecks, _) = snapshot()
        let recorderDiagnostics = recorders.flatMap { recorder in
            var issues: [TestDoubleIssue] = []
            if checkingUnusedRegistrations,
                let diagnostic = recorder.unusedRegistrationsDiagnostic()
            {
                issues.append(
                    TestDoubleIssue(
                        kind: .unusedRegistrations,
                        message: diagnostic,
                        testDoubleName: recorder.testDoubleName
                    )
                )
            }
            if checkingUnverifiedInteractions,
                let diagnostic = recorder.unverifiedInteractionsDiagnostic()
            {
                issues.append(
                    TestDoubleIssue(
                        kind: .unverifiedInteractions,
                        message: diagnostic,
                        testDoubleName: recorder.testDoubleName
                    )
                )
            }
            if checkingUnfinishedAsyncInvocations,
                let diagnostic = recorder.unfinishedAsyncInvocationsDiagnostic()
            {
                issues.append(
                    TestDoubleIssue(
                        kind: .unfinishedAsyncInvocations,
                        message: diagnostic,
                        testDoubleName: recorder.testDoubleName
                    )
                )
            }
            return issues
        }
        var enabledChecks: Set<TestDoubleTeardownCheck.Kind> = []
        if checkingUnconsumedBehaviorQueues { enabledChecks.insert(.behaviorQueue) }
        if checkingPendingSuspensions { enabledChecks.insert(.suspension) }
        if checkingPendingCallbackCaptures { enabledChecks.insert(.callbackCapture) }
        if checkingEscapedTestDoubles { enabledChecks.insert(.testDoubleLifetime) }
        if checkingUnconsumedInvocationStreams { enabledChecks.insert(.invocationStream) }
        if checkingOpenStreamControllers { enabledChecks.insert(.streamController) }
        let lifecycleIssues: [TestDoubleIssue] = teardownChecks.compactMap { teardownCheck in
            guard enabledChecks.contains(teardownCheck.kind) else {
                return nil
            }
            guard let diagnostic = teardownCheck.makeDiagnostic() else { return nil }
            return TestDoubleIssue(
                kind: issueKind(for: teardownCheck.kind),
                message: diagnostic
            )
        }
        return recorderDiagnostics + lifecycleIssues
    }

    /// Returns nonempty interaction timelines and changed fixture comparisons
    /// for Swift Testing to record as text attachments.
    @_spi(Testing) public func failureAttachments() -> [TestDoubleFailureAttachment] {
        let (recorders, _, fixtureDiffChecks) = snapshot()
        let timelines = recorders.enumerated().compactMap {
            index,
            recorder -> TestDoubleFailureAttachment? in
            let timeline = recorder.interactionTimeline()
            guard timeline.events.isEmpty == false else { return nil }
            let label =
                recorder.testDoubleName.map(sanitizedAttachmentComponent)
                ?? "test-double-\(index + 1)"
            return TestDoubleFailureAttachment(
                name: "\(label)-timeline.txt",
                contents: timeline.description
            )
        }
        let fixtureDiffs = fixtureDiffChecks.compactMap {
            check -> TestDoubleFailureAttachment? in
            guard let difference = check.makeDifference() else { return nil }
            return TestDoubleFailureAttachment(
                name: "\(sanitizedAttachmentComponent(check.name))-fixture.diff",
                contents: difference
            )
        }
        return timelines + fixtureDiffs
    }

    private func snapshot() -> (
        [StubRecorder],
        [TestDoubleTeardownCheck],
        [TestDoubleFixtureDiffCheck]
    ) {
        lock.lock()
        let recorders = recorders
        let checks = teardownChecks
        let fixtureDiffChecks = fixtureDiffChecks
        lock.unlock()
        return (recorders, checks, fixtureDiffChecks)
    }

    private func issueKind(for kind: TestDoubleTeardownCheck.Kind) -> TestDoubleIssue.Kind {
        switch kind {
            case .behaviorQueue: .unconsumedBehaviorQueue
            case .suspension: .pendingSuspension
            case .callbackCapture: .pendingCallbackCapture
            case .testDoubleLifetime: .escapedTestDouble
            case .invocationStream: .unconsumedInvocationStream
            case .streamController: .openStreamController
        }
    }
}

private func sanitizedAttachmentComponent(_ value: String) -> String {
    let scalars = value.unicodeScalars.map { scalar -> Character in
        if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
            return Character(String(scalar))
        }
        return "-"
    }
    let collapsed = String(scalars).split(separator: "-", omittingEmptySubsequences: true)
        .joined(separator: "-")
    return collapsed.isEmpty ? "test-double" : collapsed
}

/// The task-local session supplied by the opt-in `TestDoublesTesting` product.
@_spi(Testing) public enum TestDoubleTestingContext {
    /// The active automatic test-double session, if the current task has one.
    @TaskLocal public static var session: TestDoubleSession?
}

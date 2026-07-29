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

/// Per-test state used by the opt-in `TestDoublesTesting` product.
///
/// This SPI keeps Swift Testing out of the main `TestDoubles` product, which
/// continues to support the package's complete deployment range.
@_spi(Testing) public final class TestDoubleSession: @unchecked Sendable {
    private let lock = NSLock()
    private var recorders: [StubRecorder] = []
    private var teardownChecks: [TestDoubleTeardownCheck] = []

    /// Creates an empty test-double session.
    @_spi(Testing) public init() {}

    func register(_ recorder: StubRecorder) {
        lock.lock()
        defer { lock.unlock() }
        guard recorders.contains(where: { $0 === recorder }) == false else { return }
        recorders.append(recorder)
    }

    func register(_ teardownCheck: TestDoubleTeardownCheck) {
        lock.lock()
        defer { lock.unlock() }
        teardownChecks.append(teardownCheck)
    }

    /// Returns diagnostics for the requested automatic teardown checks.
    @_spi(Testing) public func diagnostics(
        checkingUnusedRegistrations: Bool,
        checkingUnverifiedInteractions: Bool,
        checkingUnconsumedBehaviorQueues: Bool = false,
        checkingPendingSuspensions: Bool = false,
        checkingPendingCallbackCaptures: Bool = false
    ) -> [String] {
        let (recorders, teardownChecks) = snapshot()
        let recorderDiagnostics = recorders.flatMap { recorder in
            var diagnostics: [String] = []
            if checkingUnusedRegistrations,
                let diagnostic = recorder.unusedRegistrationsDiagnostic()
            {
                diagnostics.append(describing(recorder: recorder, diagnostic: diagnostic))
            }
            if checkingUnverifiedInteractions,
                let diagnostic = recorder.unverifiedInteractionsDiagnostic()
            {
                diagnostics.append(describing(recorder: recorder, diagnostic: diagnostic))
            }
            return diagnostics
        }
        var enabledChecks: Set<TestDoubleTeardownCheck.Kind> = []
        if checkingUnconsumedBehaviorQueues { enabledChecks.insert(.behaviorQueue) }
        if checkingPendingSuspensions { enabledChecks.insert(.suspension) }
        if checkingPendingCallbackCaptures { enabledChecks.insert(.callbackCapture) }
        let lifecycleDiagnostics: [String] = teardownChecks.compactMap { teardownCheck -> String? in
            guard enabledChecks.contains(teardownCheck.kind) else {
                return nil
            }
            return teardownCheck.makeDiagnostic()
        }
        return recorderDiagnostics + lifecycleDiagnostics
    }

    private func snapshot() -> ([StubRecorder], [TestDoubleTeardownCheck]) {
        lock.lock()
        let recorders = recorders
        let checks = teardownChecks
        lock.unlock()
        return (recorders, checks)
    }

    private func describing(recorder: StubRecorder, diagnostic: String) -> String {
        guard let name = recorder.testDoubleName else { return diagnostic }
        return "Test double '\(name)':\n\(diagnostic)"
    }
}

/// The task-local session supplied by the opt-in `TestDoublesTesting` product.
@_spi(Testing) public enum TestDoubleTestingContext {
    /// The active automatic test-double session, if the current task has one.
    @TaskLocal public static var session: TestDoubleSession?
}

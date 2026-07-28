import Foundation

/// Per-test state used by the opt-in `TestDoublesTesting` product.
///
/// This SPI keeps Swift Testing out of the main `TestDoubles` product, which
/// continues to support the package's complete deployment range.
@_spi(Testing) public final class TestDoubleSession: @unchecked Sendable {
    private let lock = NSLock()
    private var recorders: [StubRecorder] = []

    /// Creates an empty test-double session.
    @_spi(Testing) public init() {}

    func register(_ recorder: StubRecorder) {
        lock.lock()
        defer { lock.unlock() }
        guard recorders.contains(where: { $0 === recorder }) == false else { return }
        recorders.append(recorder)
    }

    /// Returns diagnostics for the requested automatic teardown checks.
    @_spi(Testing) public func diagnostics(
        checkingUnusedRegistrations: Bool,
        checkingUnverifiedInteractions: Bool
    ) -> [String] {
        withRecorders { recorders in
            recorders.flatMap { recorder in
                var diagnostics: [String] = []
                if checkingUnusedRegistrations,
                    let diagnostic = recorder.unusedRegistrationsDiagnostic()
                {
                    diagnostics.append(diagnostic)
                }
                if checkingUnverifiedInteractions,
                    let diagnostic = recorder.unverifiedInteractionsDiagnostic()
                {
                    diagnostics.append(diagnostic)
                }
                return diagnostics
            }
        }
    }

    private func withRecorders<Result>(_ operation: ([StubRecorder]) -> Result) -> Result {
        lock.lock()
        let snapshot = recorders
        lock.unlock()
        return operation(snapshot)
    }
}

/// The task-local session supplied by the opt-in `TestDoublesTesting` product.
@_spi(Testing) public enum TestDoubleTestingContext {
    /// The active automatic test-double session, if the current task has one.
    @TaskLocal public static var session: TestDoubleSession?
}

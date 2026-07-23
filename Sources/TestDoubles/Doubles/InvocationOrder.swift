import Foundation
import IssueReporting

/// Verifies that interactions happened in a given order across any number of
/// test doubles.
///
/// Each `verify` call finds the earliest recorded invocation that matches its
/// expectation and happened after the previously verified one, then advances
/// the session's cursor there. Unrelated calls may appear between verified
/// ones, like `verifyInOrder` on a single double:
///
/// ```swift
/// let order = InvocationOrder()
/// order.verify(gateway) { $0.charge(amount: equal(42)) }
/// order.verify(analytics) { $0.track(event: equal("purchase")) }
/// ```
///
/// A failed step reports a test issue at its own call site and leaves the
/// cursor unchanged. Successful steps commit captors and count as
/// verification for `verifyNoMoreInteractions()`, both the per-double method
/// and this type's own ``verifyNoMoreInteractions(fileID:filePath:line:column:)``.
public final class InvocationOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var cursor: UInt64 = 0
    private var touchedRecorders: [ObjectIdentifier: StubRecorder] = [:]

    public init() {}

    /// Verifies the next in-order interaction on a runtime stub or spy.
    public func verify<P, Result>(
        _ stub: Stub<P>,
        _ call: (P) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        advance(
            recording: stub.recordInvocation(call),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies the next in-order async interaction on a runtime stub or spy.
    public func verify<P, Result>(
        _ stub: Stub<P>,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        advance(
            recording: await stub.recordAsyncInvocation(call, isolation: isolation),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies the next in-order interaction on a manual stub.
    public func verify<T, Result>(
        _ stub: ManualStub<T>,
        _ call: (T) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        advance(
            recording: stub.recordInvocation(call),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies the next in-order async interaction on a manual stub.
    public func verify<T, Result>(
        _ stub: ManualStub<T>,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        advance(
            recording: await stub.recordAsyncInvocation(call, isolation: isolation),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Reports every recorded invocation, across every double this session has
    /// verified at least once, that has not been covered by a successful
    /// verification.
    ///
    /// This is the cross-double counterpart to `Stub.verifyNoMoreInteractions()`
    /// and `ManualStub.verifyNoMoreInteractions()`: a test that checks several
    /// doubles together through one `InvocationOrder` can close them out
    /// together too, instead of calling each double's own method in turn.
    ///
    /// ```swift
    /// let order = InvocationOrder()
    /// order.verify(gateway) { $0.charge(amount: equal(42)) }
    /// order.verify(analytics) { $0.track(event: equal("purchase")) }
    /// order.verifyNoMoreInteractions()
    /// ```
    ///
    /// A double this session never verified is not included, even if it has
    /// recorded interactions of its own; call its own `verifyNoMoreInteractions()`
    /// for that. Every reported diagnostic points at this call's own source
    /// location, same as the per-double method.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let recorders = lock.withLock { Array(touchedRecorders.values) }
        for recorder in recorders {
            guard let diagnostic = recorder.unverifiedInteractionsDiagnostic() else {
                continue
            }
            reportIssue(
                diagnostic,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }
    }

    private func advance(
        recording: RecordedCall,
        recorder: StubRecorder,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock { touchedRecorders[ObjectIdentifier(recorder)] = recorder }
        while true {
            let currentCursor = lock.withLock { cursor }
            guard
                let match = recorder.earliestOrderedMatch(
                    recording: recording,
                    after: currentCursor
                )
            else {
                reportIssue(
                    "Ordered verification failed: no call to \(recording.name) matching "
                        + "the expectation was recorded after the previously verified "
                        + "interaction.",
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
                return
            }

            let advanced = lock.withLock {
                guard cursor == currentCursor else { return false }
                cursor = Swift.max(cursor, match.call.sequence ?? cursor)
                return true
            }
            guard advanced else { continue }

            recorder.commitSuccessfulVerification(of: [match])
            return
        }
    }
}

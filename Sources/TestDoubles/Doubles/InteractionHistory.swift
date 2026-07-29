import IssueReporting

/// A whole-double view of recorded interactions.
///
/// `history` complements the call-specific handle returned by `when`: use it
/// when the assertion concerns every call crossing a double, or compose
/// ``forwarded`` and ``stubbed`` to inspect a spy's dispatch boundary.
///
/// ```swift
/// #expect(spy.history.callCount == 3)
/// spy.history.forwarded.verify(2 ... 2)
/// spy.history.stubbed.verify()
/// print(spy.history.timeline)
/// ```
///
/// Every query is observational. Successful verification marks the matching
/// calls as verified for `verifyNoMoreInteractions()`.
public struct InteractionHistory: Sendable, CustomStringConvertible {
    let recorder: StubRecorder
    let origin: InvocationOrigin?

    init(recorder: StubRecorder, origin: InvocationOrigin? = nil) {
        self.recorder = recorder
        self.origin = origin
    }

    /// The number of calls in this history view.
    ///
    /// Reading the count does not mark calls as verified.
    public var callCount: Int {
        calls.count
    }

    /// Whether this history view contains at least one call.
    ///
    /// Reading this value does not mark calls as verified.
    public var wasCalled: Bool {
        callCount > 0
    }

    /// Calls that a spy delegated to its real target.
    ///
    /// This view is empty for a stub without a forwarding target.
    public var forwarded: Self {
        Self(recorder: recorder, origin: .forwarded)
    }

    /// Calls answered by configured behavior rather than delegated to a spy's
    /// real target.
    ///
    /// This is every call for an ordinary or manual stub.
    public var stubbed: Self {
        Self(recorder: recorder, origin: .stubbed)
    }

    /// A chronological diagnostic view of the calls in this history.
    public var timeline: InteractionTimeline {
        InteractionTimeline(calls: calls)
    }

    /// A diagnostic timeline sorted by handler completion rather than entry.
    ///
    /// Calls that remain pending appear after completed calls.
    public var completionTimeline: InteractionTimeline {
        InteractionTimeline(calls: calls, orderedByCompletion: true)
    }

    /// A compact ordered log of the calls in this history.
    ///
    /// Reading the description does not mark calls as verified.
    public var description: String {
        StubRecorderDiagnostics.interactionLog(calls)
    }

    /// Verifies the number of calls in this history, expecting exactly one by
    /// default.
    ///
    /// Successful verification marks every call in the current view as
    /// verified. A mismatch reports an issue at the caller without terminating
    /// the test process.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let calls = calls
        guard expectedCounts.contains(calls.count) else {
            reportIssue(
                "Interaction history: expected \(callCountDescription(for: expectedCounts))"
                    + dispatchExpectationDescription
                    + ", got \(calls.count)",
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
        recorder.commitInteractionHistoryVerification(calls)
    }

    /// Reports calls in this history view that have not been covered by a
    /// successful verification.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        guard
            let diagnostic = recorder.unverifiedInteractionsDiagnostic(origin: origin)
        else {
            return
        }
        reportIssue(
            diagnostic,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    private var calls: [RecordedCall] {
        recorder.interactionHistoryCalls(origin: origin)
    }

    private var dispatchExpectationDescription: String {
        switch origin {
            case .stubbed:
                " to be stubbed"
            case .forwarded:
                " to be forwarded"
            case nil:
                ""
        }
    }
}

extension Stub {
    /// A whole-double view of every recorded interaction.
    public var history: InteractionHistory {
        InteractionHistory(recorder: recorder)
    }
}

extension ManualStub {
    /// A whole-double view of every recorded interaction.
    public var history: InteractionHistory {
        InteractionHistory(recorder: recorder)
    }
}

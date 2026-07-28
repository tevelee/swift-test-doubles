import IssueReporting

/// An inspectable, per-registration queue of fixed behaviors.
///
/// Obtain this handle from ``StubBuilder/thenQueue(_:_:)`` or from a
/// ``StubBehaviorChain``'s ``StubBehaviorChain/behaviorQueue`` property.
/// A finite queue is useful for retry tests: assert that every planned
/// failure was consumed instead of silently leaving a recovery path untested.
public final class StubBehaviorQueue: @unchecked Sendable {
    private let sequence: StubRecorder.ConsumableResults

    init(sequence: StubRecorder.ConsumableResults) {
        self.sequence = sequence
    }

    /// Remaining finite answers, or `nil` when the queue has an unbounded
    /// terminal behavior that will keep answering matching calls.
    public var remainingAnswerCount: Int? {
        sequence.remainingAnswerCount()
    }

    /// Whether a finite queue has delivered every configured answer.
    ///
    /// An unbounded queue is never considered exhausted because it always has
    /// another answer available.
    public var isExhausted: Bool {
        sequence.isFiniteQueueExhausted()
    }

    /// Reports a test issue unless every finite queued answer was consumed.
    public func assertExhausted(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        guard let remaining = remainingAnswerCount else {
            reportIssue(
                "[TestDoubles] Cannot assert exhaustion for an unbounded behavior queue.",
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
        guard remaining > 0 else { return }
        reportIssue(
            "[TestDoubles] Expected every queued behavior to be consumed, but \(remaining) "
                + "\(remaining == 1 ? "answer remains" : "answers remain").",
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

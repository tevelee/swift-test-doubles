import Foundation
import IssueReporting

/// Verifies handler completion order independently from invocation-entry order.
///
/// Save call patterns during setup, run the calls, then list the patterns in
/// the order their handlers are expected to return, throw, or finish
/// forwarding:
///
/// ```swift
/// CompletionOrder {
///     fastLoad
///     slowLoad
/// }
/// ```
public final class CompletionOrder: @unchecked Sendable {
    /// A type-erased saved interaction used by ``Builder``.
    public struct Expectation: Sendable {
        fileprivate let interactions: CallInteractions
        fileprivate let location: StubSourceLocation
    }

    /// Builds a completion sequence from saved patterns and terminal handles.
    @resultBuilder
    public enum Builder {
        /// Adds a saved call pattern.
        public static func buildExpression<Result>(
            _ pattern: CallPattern<Result>,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            expectation(
                pattern.interactions,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Adds a saved unary-closure pattern.
        public static func buildExpression<Input, Result>(
            _ pattern: ClosureCallPattern<Input, Result>,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            buildExpression(
                pattern.base,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Adds a saved throwing-closure pattern.
        public static func buildExpression<Input, Result>(
            _ pattern: ThrowingClosureCallPattern<Input, Result>,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            buildExpression(
                pattern.base,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Adds a saved async-closure pattern.
        public static func buildExpression<Input, Result>(
            _ pattern: AsyncClosureCallPattern<Input, Result>,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            buildExpression(
                pattern.base,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Adds a saved async-throwing closure pattern.
        public static func buildExpression<Input, Result>(
            _ pattern: AsyncThrowingClosureCallPattern<Input, Result>,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            buildExpression(
                pattern.base,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Adds a terminal interaction handle.
        public static func buildExpression(
            _ interactions: CallInteractions,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            expectation(
                interactions,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Combines expressions in source order.
        public static func buildBlock(
            _ components: [Expectation]...
        ) -> [Expectation] {
            components.flatMap(\.self)
        }

        /// Includes an optional group.
        public static func buildOptional(
            _ component: [Expectation]?
        ) -> [Expectation] {
            component ?? []
        }

        /// Selects the first conditional branch.
        public static func buildEither(
            first component: [Expectation]
        ) -> [Expectation] {
            component
        }

        /// Selects the second conditional branch.
        public static func buildEither(
            second component: [Expectation]
        ) -> [Expectation] {
            component
        }

        /// Flattens loop-produced expectations.
        public static func buildArray(
            _ components: [[Expectation]]
        ) -> [Expectation] {
            components.flatMap(\.self)
        }

        private static func expectation(
            _ interactions: CallInteractions,
            fileID: StaticString,
            filePath: StaticString,
            line: UInt,
            column: UInt
        ) -> [Expectation] {
            [
                Expectation(
                    interactions: interactions,
                    location: StubSourceLocation(
                        fileID: fileID,
                        filePath: filePath,
                        line: line,
                        column: column
                    )
                )
            ]
        }
    }

    private let lock = NSLock()
    private var cursor: UInt64 = 0

    /// Creates an empty completion-order verification session.
    public init() {}

    /// Verifies saved interactions in completion order.
    @discardableResult
    public convenience init(
        @Builder _ expectations: () -> [Expectation]
    ) {
        self.init()
        for expectation in expectations() {
            advance(
                expectation.interactions,
                fileID: expectation.location.fileID,
                filePath: expectation.location.filePath,
                line: expectation.location.line,
                column: expectation.location.column
            )
        }
    }

    /// Verifies a saved call pattern after the previous completion.
    @discardableResult
    public func verify<Result>(
        _ pattern: CallPattern<Result>,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        verify(
            pattern.interactions,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies terminal interactions after the previous completion.
    @discardableResult
    public func verify(
        _ interactions: CallInteractions,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        advance(
            interactions,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
    }

    private func advance(
        _ interactions: CallInteractions,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        while true {
            let currentCursor = lock.withLock { cursor }
            guard
                let match = interactions.recorder.earliestCompletionOrderedMatch(
                    recording: interactions.recording,
                    after: currentCursor,
                    origin: interactions.origin
                )
            else {
                reportIssue(
                    "Completion-order verification failed: no completed call to "
                        + "\(interactions.recording.name) matching the expectation "
                        + "was recorded after the previously verified completion.",
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
                return
            }

            let advanced = lock.withLock {
                guard cursor == currentCursor else { return false }
                cursor = Swift.max(
                    cursor,
                    match.call.completionSequence ?? cursor
                )
                return true
            }
            guard advanced else { continue }
            interactions.recorder.commitSuccessfulVerification(of: [match])
            return
        }
    }
}

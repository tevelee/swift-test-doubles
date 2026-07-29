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
/// let charges = gateway.when {
///     $0.charge(amount: Match.equal(42))
/// }
/// charges.thenDoNothing()
/// let purchases = analytics.when {
///     $0.track(event: Match.equal("purchase"))
/// }.thenDoNothing()
///
/// InvocationOrder()
///     .verify(charges)
///     .verify(purchases)
/// ```
///
/// When every interaction on the participating doubles matters, use the
/// scoped exhaustive form. Repeat the expected invocations directly:
///
/// ```swift
/// InvocationOrder(exhaustive: true) {
///     gateway().charge(amount: 42)
///     analytics().track(event: "purchase")
/// }
/// ```
///
/// Saved patterns can be listed instead when setup, behavior, ordering, and
/// later argument inspection should share one call description.
///
/// A failed step reports a test issue at its own call site and leaves the
/// cursor unchanged. Successful steps commit captors and count as
/// verification for `verifyNoMoreInteractions()`, both the per-double method
/// and this type's own ``verifyNoMoreInteractions(fileID:filePath:line:column:)``.
public final class InvocationOrder: @unchecked Sendable {
    /// A type-erased saved interaction used by ``Builder``.
    ///
    /// Values are created implicitly from call patterns and
    /// ``CallInteractions`` inside a scoped `InvocationOrder`.
    public struct Expectation: Sendable {
        fileprivate let interactions: CallInteractions
        fileprivate let location: StubSourceLocation
    }

    /// Builds an ordered list from direct test-double invocations, saved call
    /// patterns, and terminal ``CallInteractions`` values.
    @resultBuilder
    public enum Builder {
        /// Adds a general saved call pattern to the ordered expectation.
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

        /// Adds a saved unary-closure pattern to the ordered expectation.
        public static func buildExpression<Input, Result>(
            _ pattern: ClosureCallPattern<Input, Result>,
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

        /// Adds a saved throwing-closure pattern to the ordered expectation.
        public static func buildExpression<Input, Result>(
            _ pattern: ThrowingClosureCallPattern<Input, Result>,
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

        /// Adds a saved async-closure pattern to the ordered expectation.
        public static func buildExpression<Input, Result>(
            _ pattern: AsyncClosureCallPattern<Input, Result>,
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

        /// Adds a saved async-throwing closure pattern to the ordered
        /// expectation.
        public static func buildExpression<Input, Result>(
            _ pattern: AsyncThrowingClosureCallPattern<Input, Result>,
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

        /// Adds terminal behavior interactions to the ordered expectation.
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

        /// Adds a protocol or closure-double invocation written directly in
        /// the builder.
        ///
        /// The invocation runs in capture mode: it describes an expectation
        /// and does not add another interaction to the double.
        public static func buildExpression<Value>(
            _ value: Value,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) -> [Expectation] {
            _ = value
            guard let captured = StubCaptureCoordinator.takeBuilderCall() else {
                preconditionFailure(
                    "[TestDoubles] InvocationOrder builder expressions must be "
                        + "saved call patterns or direct test-double invocations."
                )
            }
            return expectation(
                captured,
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

        /// Includes an optional group when its condition is true.
        public static func buildOptional(
            _ component: [Expectation]?
        ) -> [Expectation] {
            component ?? []
        }

        /// Selects the first branch of a conditional group.
        public static func buildEither(
            first component: [Expectation]
        ) -> [Expectation] {
            component
        }

        /// Selects the second branch of a conditional group.
        public static func buildEither(
            second component: [Expectation]
        ) -> [Expectation] {
            component
        }

        /// Flattens expectations produced by a loop.
        public static func buildArray(
            _ components: [[Expectation]]
        ) -> [Expectation] {
            components.flatMap(\.self)
        }

        /// Preserves a group guarded by an availability check.
        public static func buildLimitedAvailability(
            _ component: [Expectation]
        ) -> [Expectation] {
            component
        }

        private static func expectation(
            _ interactions: CallInteractions,
            fileID: StaticString,
            filePath: StaticString,
            line: UInt,
            column: UInt
        ) -> [Expectation] {
            if let captured = StubCaptureCoordinator.takeBuilderCall() {
                return expectation(
                    captured,
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            }
            return [
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

        private static func expectation(
            _ captured: CapturedStubCall,
            fileID: StaticString,
            filePath: StaticString,
            line: UInt,
            column: UInt
        ) -> [Expectation] {
            [
                Expectation(
                    interactions: CallInteractions(
                        recorder: captured.recorder,
                        recording: captured.call
                    ),
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
    private var touchedRecorders: [ObjectIdentifier: StubRecorder] = [:]

    /// Creates a session with no verified interactions yet.
    public init() {}

    /// Verifies direct test-double invocations or saved patterns in source
    /// order.
    ///
    /// Calls written in the builder run in capture mode and do not record new
    /// interactions. With `exhaustive` set to `true`, the initializer also
    /// reports every interaction left unverified on a double that participated
    /// in the sequence. The default accepts a subsequence, so unrelated
    /// interactions may appear before, between, or after the expectations.
    @discardableResult
    public convenience init(
        exhaustive: Bool = false,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        @Builder _ expectations: () throws -> [Expectation]
    ) rethrows {
        self.init()
        let (built, remainingMatchers) = try MatcherContext.withRecording {
            try StubCaptureCoordinator.captureAll(expectations)
        }
        precondition(
            remainingMatchers.isEmpty,
            "[TestDoubles] A matcher was created but not passed to a protocol "
                + "requirement in the InvocationOrder builder."
        )
        for expectation in built {
            advance(
                recording: expectation.interactions.recording,
                recorder: expectation.interactions.recorder,
                origin: expectation.interactions.origin,
                fileID: expectation.location.fileID,
                filePath: expectation.location.filePath,
                line: expectation.location.line,
                column: expectation.location.column
            )
        }
        guard exhaustive else { return }
        verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Asynchronously verifies saved patterns or direct invocations in source
    /// order.
    ///
    /// Async and throwing calls may be written directly in the builder. With
    /// `exhaustive` set to `true`, every interaction on each participating
    /// double must be listed.
    @_disfavoredOverload
    @discardableResult
    public convenience init(
        exhaustive: Bool = false,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        @Builder _ expectations: () async throws -> [Expectation]
    ) async rethrows {
        self.init()
        let (built, remainingMatchers) = try await MatcherContext.withRecording(
            isolation: isolation
        ) {
            try await StubCaptureCoordinator.captureAll(
                isolation: isolation,
                expectations
            )
        }
        precondition(
            remainingMatchers.isEmpty,
            "[TestDoubles] A matcher was created but not passed to a protocol "
                + "requirement in the InvocationOrder builder."
        )
        for expectation in built {
            advance(
                recording: expectation.interactions.recording,
                recorder: expectation.interactions.recorder,
                origin: expectation.interactions.origin,
                fileID: expectation.location.fileID,
                filePath: expectation.location.filePath,
                line: expectation.location.line,
                column: expectation.location.column
            )
        }
        guard exhaustive else { return }
        verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Runs several ordered verifications in one synchronous scope.
    ///
    /// Use this form when an expectation was not saved during setup. With
    /// `exhaustive` set to `true`, every interaction on the doubles touched by
    /// a successful verification must be covered when `verification` returns.
    @discardableResult
    public convenience init(
        exhaustive: Bool = false,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ verification: (InvocationOrder) throws -> Void
    ) rethrows {
        self.init()
        try verification(self)
        guard exhaustive else { return }
        verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Runs several ordered verifications in one asynchronous scope.
    ///
    /// This overload accepts async requirement recordings. With `exhaustive`
    /// set to `true`, every interaction on the doubles touched by a successful
    /// verification must be covered when `verification` returns.
    @_disfavoredOverload
    @discardableResult
    public convenience init(
        exhaustive: Bool = false,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column,
        _ verification: (InvocationOrder) async throws -> Void
    ) async rethrows {
        self.init()
        try await verification(self)
        guard exhaustive else { return }
        verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that `pattern` has a matching interaction after the
    /// previously verified interaction.
    ///
    /// Saving a `when` pattern lets behavior configuration, ordinary
    /// verification, and cross-double ordering share one call description.
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

    /// Verifies that a saved unary-closure pattern has a matching interaction
    /// after the previously verified interaction.
    @discardableResult
    public func verify<Input, Result>(
        _ pattern: ClosureCallPattern<Input, Result>,
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

    /// Verifies that a saved throwing-closure pattern has a matching
    /// interaction after the previously verified interaction.
    @discardableResult
    public func verify<Input, Result>(
        _ pattern: ThrowingClosureCallPattern<Input, Result>,
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

    /// Verifies that a saved async-closure pattern has a matching interaction
    /// after the previously verified interaction.
    @discardableResult
    public func verify<Input, Result>(
        _ pattern: AsyncClosureCallPattern<Input, Result>,
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

    /// Verifies that a saved async-throwing closure pattern has a matching
    /// interaction after the previously verified interaction.
    @discardableResult
    public func verify<Input, Result>(
        _ pattern: AsyncThrowingClosureCallPattern<Input, Result>,
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

    /// Verifies that `interactions` has a matching call after the previously
    /// verified interaction.
    ///
    /// Terminal `then` methods return this handle, so an inline fluent
    /// configuration can be reused for ordering without recording its call
    /// again.
    @discardableResult
    public func verify(
        _ interactions: CallInteractions,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        advance(
            recording: interactions.recording,
            recorder: interactions.recorder,
            origin: interactions.origin,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
    }

    /// Verifies the next in-order interaction on a runtime stub or spy.
    @discardableResult
    public func verify<P, Result>(
        _ stub: Stub<P>,
        _ call: (P) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        advance(
            recording: stub.recordInvocation(call),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
    }

    /// Verifies the next in-order async interaction on a runtime stub or spy.
    @discardableResult
    public func verify<P, Result>(
        _ stub: Stub<P>,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async -> Self {
        advance(
            recording: await stub.recordAsyncInvocation(call, isolation: isolation),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
    }

    /// Verifies the next in-order interaction on a manual stub.
    @discardableResult
    public func verify<T, Result>(
        _ stub: ManualStub<T>,
        _ call: (T) throws -> Result,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
        advance(
            recording: stub.recordInvocation(call),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
    }

    /// Verifies the next in-order async interaction on a manual stub.
    @discardableResult
    public func verify<T, Result>(
        _ stub: ManualStub<T>,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async -> Self {
        advance(
            recording: await stub.recordAsyncInvocation(call, isolation: isolation),
            recorder: stub.recorder,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
        return self
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
    /// InvocationOrder()
    ///     .verify(gateway) { $0.charge(amount: Match.equal(42)) }
    ///     .verify(analytics) { $0.track(event: Match.equal("purchase")) }
    ///     .verifyNoMoreInteractions()
    /// ```
    ///
    /// A double this session never verified is not included, even if it has
    /// recorded interactions of its own; call its own `verifyNoMoreInteractions()`
    /// for that. Every reported diagnostic points at this call's own source
    /// location, same as the per-double method.
    @discardableResult
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> Self {
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
        return self
    }

    private func advance(
        recording: RecordedCall,
        recorder: StubRecorder,
        origin: InvocationOrigin? = nil,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        while true {
            let currentCursor = lock.withLock { cursor }
            guard
                let match = recorder.earliestOrderedMatch(
                    recording: recording,
                    after: currentCursor,
                    origin: origin
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
                touchedRecorders[ObjectIdentifier(recorder)] = recorder
                return true
            }
            guard advanced else { continue }

            recorder.commitSuccessfulVerification(of: [match])
            return
        }
    }
}

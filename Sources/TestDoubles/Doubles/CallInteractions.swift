/// An observation-only handle for every invocation matching one recorded call.
///
/// Terminal behaviors return this value so a complete fluent configuration can
/// be saved and inspected later. Unbounded fixed terminals additionally prevent
/// another behavior from being appended:
///
/// ```swift
/// let loads = stub.when { try $0.load() }
///     .thenThrow(APIError(), times: 2)
///     .thenReturn("fallback")
///
/// loads.verify(3...)
/// ```
public struct CallInteractions: Sendable {
    let recorder: StubRecorder
    let recording: RecordedCall

    private var pattern: CallPattern<Void> {
        CallPattern(recorder: recorder, recording: recording)
    }

    /// The number of recorded invocations matching this call.
    ///
    /// Reading the count does not mark calls as verified or commit captures.
    public var callCount: Int {
        pattern.callCount
    }

    /// Whether at least one recorded invocation matches this call.
    ///
    /// Reading this value does not mark calls as verified or commit captures.
    public var wasCalled: Bool {
        pattern.wasCalled
    }

    /// Matching interactions that a spy delegated to its real target.
    ///
    /// This view is empty for a stub without a forwarding target.
    public var forwarded: Forwarded {
        Forwarded(base: pattern.forwarded)
    }

    /// Verifies how many recorded invocations match this call.
    ///
    /// Successful verification marks every matching call as verified and
    /// commits captures. A mismatch is reported at the caller's source
    /// location without terminating the test process.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1...,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        pattern.verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits up to `timeout` for the lower-bound count of matching calls.
    ///
    /// Eventual verification accepts a lower bound because it becomes true
    /// monotonically as calls arrive.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await pattern.verify(
            expectedCounts,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits for matching calls using `clock` rather than wall time.
    ///
    /// Use ``ManualStubClock`` to advance timeout-sensitive tests
    /// deterministically.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await pattern.verify(
            expectedCounts,
            within: timeout,
            using: clock,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Returns matching invocation arguments as typed tuples, in call order.
    ///
    /// Annotate the result to select the tuple shape. This is a pure query: it
    /// does not verify calls, consume behavior, or commit captures.
    public func arguments<each Argument>() -> [(repeat each Argument)] {
        pattern.arguments()
    }

    /// Returns a stream of future matching invocation arguments.
    ///
    /// Calls recorded before this method returns are deliberately excluded.
    /// Streaming is observational: it does not verify calls or commit captures.
    public func stream<each Argument>() -> InvocationStream<(repeat each Argument)> {
        pattern.stream()
    }

    /// Matching interactions that a spy forwarded to its real target.
    ///
    /// Obtain this view from ``CallInteractions/forwarded``. Calls answered
    /// by an override are excluded, and every query is empty for an ordinary
    /// stub without a forwarding target.
    public struct Forwarded: Sendable {
        private let base: CallPattern<Void>.Forwarded

        init(base: CallPattern<Void>.Forwarded) {
            self.base = base
        }

        /// The number of matching calls delegated to the forwarding target.
        public var callCount: Int {
            base.callCount
        }

        /// Whether at least one matching call reached the forwarding target.
        public var wasCalled: Bool {
            base.wasCalled
        }

        /// Verifies how many matching calls reached the forwarding target.
        public func verify(
            _ expectedCounts: any RangeExpression<Int> = 1...,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) {
            base.verify(
                expectedCounts,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Waits up to `timeout` for the lower-bound number of matching calls
        /// to reach the forwarding target.
        public func verify(
            _ expectedCounts: PartialRangeFrom<Int> = 1...,
            within timeout: Duration,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) async {
            await base.verify(
                expectedCounts,
                within: timeout,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Waits for forwarded calls using `clock` rather than wall time.
        public func verify(
            _ expectedCounts: PartialRangeFrom<Int> = 1...,
            within timeout: Duration,
            using clock: any StubClock,
            fileID: StaticString = #fileID,
            filePath: StaticString = #filePath,
            line: UInt = #line,
            column: UInt = #column
        ) async {
            await base.verify(
                expectedCounts,
                within: timeout,
                using: clock,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        }

        /// Returns arguments from matching forwarded calls, in call order.
        public func arguments<each Argument>() -> [(repeat each Argument)] {
            base.arguments()
        }

        /// Returns a stream of future matching calls that reach the target.
        public func stream<each Argument>() -> InvocationStream<(repeat each Argument)> {
            base.stream()
        }
    }
}

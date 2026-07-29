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
    let origin: InvocationOrigin?

    init(
        recorder: StubRecorder,
        recording: RecordedCall,
        origin: InvocationOrigin? = nil
    ) {
        self.recorder = recorder
        self.recording = recording
        self.origin = origin
    }

    private var pattern: CallPattern<Void> {
        CallPattern(recorder: recorder, recording: recording, origin: origin)
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
    public var forwarded: Self {
        Self(recorder: recorder, recording: recording, origin: .forwarded)
    }

    /// Matching interactions answered by configured behavior rather than
    /// delegated to a spy's real target.
    ///
    /// This is every interaction for an ordinary or manual stub. For a spy it
    /// excludes unmatched calls and explicit `thenForward()` behavior.
    public var stubbed: Self {
        Self(recorder: recorder, recording: recording, origin: .stubbed)
    }

    /// Verifies how many recorded invocations match this call, expecting
    /// exactly one by default.
    ///
    /// Successful verification marks every matching call as verified and
    /// commits captures. A mismatch is reported at the caller's source
    /// location without terminating the test process.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
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

    /// Returned values from completed matching calls.
    ///
    /// The terminal handle does not retain its result generic, so `Result`
    /// is inferred from the assignment or supplied explicitly with `as:`.
    public func results<Result>(
        as type: Result.Type = Result.self
    ) -> [Result] {
        matchingCalls().compactMap { call in
            guard case .returned(let value) = call.typedOutcome(as: type) else {
                return nil
            }
            return value
        }
    }

    /// Errors thrown by completed matching calls.
    public func errors() -> [any Error] {
        matchingCalls().compactMap { call in
            guard case .threw(let error) = call.outcome else { return nil }
            return error
        }
    }

    /// Errors of `Failure` thrown by completed matching calls.
    public func errors<Failure: Error>(
        ofType type: Failure.Type
    ) -> [Failure] {
        errors().compactMap { $0 as? Failure }
    }

    /// Completion states for matching calls.
    public func outcomes<Result>(
        as type: Result.Type = Result.self
    ) -> [InvocationOutcome<Result>] {
        matchingCalls().map { $0.typedOutcome(as: type) }
    }

    /// The most recently entered matching call's completion state.
    public func lastOutcome<Result>(
        as type: Result.Type = Result.self
    ) -> InvocationOutcome<Result>? {
        matchingCalls().last?.typedOutcome(as: type)
    }

    /// Returns a stream of future matching invocation arguments.
    ///
    /// Calls recorded before this method returns are deliberately excluded.
    /// Streaming is observational: it does not verify calls or commit captures.
    public func stream<each Argument>() -> InvocationStream<(repeat each Argument)> {
        pattern.stream()
    }

    private func matchingCalls() -> [RecordedCall] {
        recorder.verificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            origin: origin
        )
    }
}

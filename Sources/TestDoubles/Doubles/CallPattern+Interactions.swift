import IssueReporting

/// Interaction queries and verification for a recorded call pattern.
extension CallPattern {
    /// An observation-only view of the invocations matching this pattern.
    ///
    /// Behavior configuration remains available on the pattern itself. Use
    /// this view when an API needs to expose interactions without also
    /// allowing another behavior registration.
    public var interactions: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording, origin: origin)
    }

    /// The number of recorded invocations that match this pattern.
    ///
    /// Reading the count does not mark calls as verified or commit captures.
    public var callCount: Int {
        matchingCalls().count
    }

    /// Whether at least one recorded invocation matches this pattern.
    ///
    /// Reading this value does not mark calls as verified or commit captures.
    public var wasCalled: Bool {
        callCount > 0
    }

    /// Interactions matching this pattern that a spy delegated to its target.
    ///
    /// This view is empty for a stub without a forwarding target.
    public var forwarded: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording, origin: .forwarded)
    }

    /// Interactions answered by configured behavior rather than delegated to
    /// a spy's target.
    ///
    /// This is every interaction on an ordinary or manual stub.
    public var stubbed: CallInteractions {
        CallInteractions(recorder: recorder, recording: recording, origin: .stubbed)
    }

    /// Verifies how many recorded invocations match this pattern, expecting
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
        let matches = recorder.preparedVerificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            origin: origin
        )
        let actualCount = matches.count

        guard expectedCounts.contains(actualCount) else {
            var message =
                "'\(recording.name)': expected \(callCountDescription(for: expectedCounts))"
                + dispatchExpectationDescription
                + ", "
                + "got \(actualCount)"
            if origin == nil,
                let nearMisses = recorder.verificationNearMisses(for: recording)
            {
                message += "\n\n\(nearMisses)"
            }
            reportIssue(
                message,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
        recorder.commitSuccessfulVerification(of: matches)
    }

    /// Waits up to `timeout` for the lower-bound count of matching calls.
    ///
    /// Eventual verification accepts a lower bound because it becomes true
    /// monotonically as calls arrive. Calls wake this waiter directly; no
    /// polling or sleeps are needed.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        switch await recorder.waitForCallCount(
            recording: recording,
            minimumCount: expectedCounts.lowerBound,
            timeout: timeout,
            origin: origin
        ) {
            case .satisfied, .cancelled:
                return
            case .timedOut(let actualCount):
                reportTimeout(
                    expectedCounts: expectedCounts,
                    timeout: timeout,
                    actualCount: actualCount,
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
        }
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
        switch await recorder.waitForCallCount(
            recording: recording,
            minimumCount: expectedCounts.lowerBound,
            timeout: timeout,
            using: clock,
            origin: origin
        ) {
            case .satisfied, .cancelled:
                return
            case .timedOut(let actualCount):
                reportTimeout(
                    expectedCounts: expectedCounts,
                    timeout: timeout,
                    actualCount: actualCount,
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
        }
    }

    /// Returns matching invocation arguments as typed tuples, in call order.
    ///
    /// Annotate the result to select the tuple shape. Components bind from
    /// the front, so a narrower tuple reads a leading argument prefix:
    ///
    /// ```swift
    /// let pattern = analytics.when {
    ///     $0.track(event: Match.any(), value: Match.any())
    /// }
    /// let events: [(String, Int)] = pattern.arguments()
    /// ```
    ///
    /// This is a pure query: it does not verify calls, consume configured
    /// behavior, or commit captures.
    public func arguments<each Argument>() -> [(repeat each Argument)] {
        matchingCalls().map(typedCallArguments)
    }

    /// Returned values from completed matching calls, in invocation order.
    ///
    /// Pending, throwing, forwarded, and ABI-opaque outcomes are omitted.
    public func results() -> [Result] {
        matchingCalls().compactMap { call in
            guard case .returned(let value) = call.typedOutcome(as: Result.self) else {
                return nil
            }
            return value
        }
    }

    /// Errors thrown by completed matching calls, in invocation order.
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

    /// Completion states for all matching calls, in invocation order.
    public func outcomes() -> [InvocationOutcome<Result>] {
        matchingCalls().map { $0.typedOutcome(as: Result.self) }
    }

    /// The most recently entered matching call's completion state.
    public var lastOutcome: InvocationOutcome<Result>? {
        matchingCalls().last?.typedOutcome(as: Result.self)
    }

    /// Monotonic timing information for matching calls, in invocation order.
    public func timings() -> [InvocationTiming] {
        matchingCalls().compactMap(\.timing)
    }

    /// Returns a stream of future matching invocation arguments.
    ///
    /// Calls recorded before this method returns are deliberately excluded.
    /// Iteration ends when its awaiting task is cancelled. Streaming is
    /// observational: it does not verify calls or commit captures.
    public func stream<each Argument>() -> InvocationStream<(repeat each Argument)> {
        InvocationStream(
            recorder: recorder,
            recording: recording,
            origin: origin,
            transform: typedCallArguments
        )
    }

    private func matchingCalls() -> [RecordedCall] {
        recorder.verificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
            origin: origin
        )
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

    private func reportTimeout(
        expectedCounts: PartialRangeFrom<Int>,
        timeout: Duration,
        actualCount: Int,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        var message =
            "'\(recording.name)': expected \(callCountDescription(for: expectedCounts))"
            + dispatchExpectationDescription
            + " "
            + "within \(timeout), got \(actualCount)"
        if origin == nil,
            let nearMisses = recorder.verificationNearMisses(for: recording)
        {
            message += "\n\n\(nearMisses)"
        }
        reportIssue(
            message,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

func callCountDescription(for expectedCounts: any RangeExpression<Int>) -> String {
    func calls(_ count: Int) -> String {
        "\(count) \(count == 1 ? "call" : "calls")"
    }

    switch expectedCounts {
        case let range as ClosedRange<Int> where range.lowerBound == range.upperBound:
            return range.lowerBound == 0 ? "no calls" : calls(range.lowerBound)
        case let range as ClosedRange<Int>:
            return "between \(calls(range.lowerBound)) and \(calls(range.upperBound))"
        case let range as Range<Int>:
            return "at least \(calls(range.lowerBound)) and fewer than \(calls(range.upperBound))"
        case let range as PartialRangeFrom<Int>:
            return "at least \(calls(range.lowerBound))"
        case let range as PartialRangeThrough<Int>:
            return "at most \(calls(range.upperBound))"
        case let range as PartialRangeUpTo<Int>:
            return "fewer than \(calls(range.upperBound))"
        default:
            return "a count matching \(expectedCounts)"
    }
}

private func typedCallArguments<each Argument>(
    from call: RecordedCall
) -> (repeat each Argument) {
    var index = 0
    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(
            type,
            from: call.args,
            at: index,
            method: call.name,
            context: "CallPattern arguments"
        )
    }
    return (repeat nextArgument((each Argument).self))
}

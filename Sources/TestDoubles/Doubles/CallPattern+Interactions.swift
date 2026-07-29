import IssueReporting

/// Interaction queries and verification for a recorded call pattern.
extension CallPattern {
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

    /// The number of matching calls a spy forwarded to its real target.
    ///
    /// This is zero for a stub without a forwarding target. Reading the count
    /// does not mark calls as verified or commit captures.
    public var forwardedCallCount: Int {
        forwardedMatchingCalls().count
    }

    /// Verifies how many recorded invocations match this pattern.
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
        let matches = recorder.preparedVerificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
        )
        let actualCount = matches.count

        guard expectedCounts.contains(actualCount) else {
            var message =
                "'\(recording.name)': expected \(callCountDescription(for: expectedCounts)), "
                + "got \(actualCount)"
            if let nearMisses = recorder.verificationNearMisses(for: recording) {
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
            timeout: timeout
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
            using: clock
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

    /// Returns arguments from matching calls that a spy forwarded to its
    /// real target.
    ///
    /// Calls answered by an override are excluded. This returns an empty
    /// array for a stub without a forwarding target.
    public func forwardedArguments<each Argument>() -> [(repeat each Argument)] {
        forwardedMatchingCalls().map(typedCallArguments)
    }

    /// Returns a stream of future matching invocation arguments.
    ///
    /// Calls recorded before this method returns are deliberately excluded.
    /// Iteration ends when its awaiting task is cancelled. Streaming is
    /// observational: it does not verify calls or commit captures.
    public func stream<each Argument>() -> InvocationStream<(repeat each Argument)> {
        InvocationStream(recorder: recorder, recording: recording, transform: typedCallArguments)
    }

    private func matchingCalls() -> [RecordedCall] {
        recorder.verificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
        )
    }

    private func forwardedMatchingCalls() -> [RecordedCall] {
        recorder.forwardedVerificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers,
            matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
        )
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
            "'\(recording.name)': expected \(callCountDescription(for: expectedCounts)) "
            + "within \(timeout), got \(actualCount)"
        if let nearMisses = recorder.verificationNearMisses(for: recording) {
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

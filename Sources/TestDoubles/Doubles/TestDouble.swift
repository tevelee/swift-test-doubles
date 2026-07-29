import IssueReporting

/// The recording and verification core shared by ``Stub`` and ``ManualStub``.
///
/// Both doubles capture invocations through the same `StubRecorder`, so the
/// recording plumbing and call-count verification live here while each double
/// keeps its own public API surface.
protocol TestDouble {
    associatedtype Generated
    var recorder: StubRecorder { get }
    func materializeForRecording() -> Generated
}

extension Stub: TestDouble {}
extension ManualStub: TestDouble {}

// MARK: - Recording

extension TestDouble {
    func recordInvocation<Result>(
        _ call: (Generated) throws -> Result
    ) -> RecordedCall {
        record { _ = try! call(materializeForRecording()) }
    }

    func recordInvocation<Result>(
        returning placeholder: Result,
        _ call: (Generated) throws -> Result
    ) -> RecordedCall {
        record(returning: placeholder) {
            _ = try! call(materializeForRecording())
        }
    }

    func recordMutation(
        _ call: (inout Generated) throws -> Void
    ) -> RecordedCall {
        var value = materializeForRecording()
        return record { try! call(&value) }
    }

    func recordInvocations(
        _ calls: (Generated) throws -> Void
    ) -> [RecordedCall] {
        recordCalls { try! calls(materializeForRecording()) }
    }

    func recordMutatingInvocations(
        _ calls: (inout Generated) throws -> Void
    ) -> [RecordedCall] {
        var value = materializeForRecording()
        return recordCalls { try! calls(&value) }
    }

    func recordAsyncInvocation<Result>(
        _ call: (Generated) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> RecordedCall {
        await recordAsync(isolation: isolation) {
            _ = try! await call(materializeForRecording())
        }
    }

    func recordAsyncInvocation<Result>(
        returning placeholder: Result,
        _ call: (Generated) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> RecordedCall {
        await recordAsync(returning: placeholder, isolation: isolation) {
            _ = try! await call(materializeForRecording())
        }
    }

    func recordAsyncInvocations(
        _ calls: (Generated) async throws -> Void,
        isolation: isolated (any Actor)? = #isolation
    ) async -> [RecordedCall] {
        await recordCallsAsync(isolation: isolation) {
            try! await calls(materializeForRecording())
        }
    }

    func record(_ block: () -> Void) -> RecordedCall {
        singleRecording(from: recordCalls(block))
    }

    func record<Placeholder>(
        returning placeholder: Placeholder,
        _ block: () -> Void
    ) -> RecordedCall {
        RecordingReturnPlaceholderContext.withValue(placeholder) {
            record(block)
        }
    }

    func recordAsync(
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async -> Void
    ) async -> RecordedCall {
        singleRecording(from: await recordCallsAsync(isolation: isolation, block))
    }

    func recordAsync<Placeholder>(
        returning placeholder: Placeholder,
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async -> Void
    ) async -> RecordedCall {
        await RecordingReturnPlaceholderContext.withValue(
            placeholder,
            isolation: isolation
        ) {
            await recordAsync(isolation: isolation, block)
        }
    }

    func recordCalls(_ block: () -> Void) -> [RecordedCall] {
        let (recordings, remainingMatchers) = MatcherContext.withRecording {
            recorder.captureCalls(block)
        }
        precondition(
            remainingMatchers.isEmpty,
            "[TestDoubles] A matcher was created but not passed to a protocol requirement. "
                + "Move every matcher inside the recorded invocation, or remove the unused matcher."
        )
        return recordings
    }

    func recordCallsAsync(
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async -> Void
    ) async -> [RecordedCall] {
        let (recordings, remainingMatchers) = await MatcherContext.withRecording(
            isolation: isolation
        ) {
            await recorder.captureCalls(isolation: isolation, block)
        }
        precondition(
            remainingMatchers.isEmpty,
            "[TestDoubles] A matcher was created but not passed to a protocol requirement. "
                + "Move every matcher inside the recorded invocation, or remove the unused matcher."
        )
        return recordings
    }

    private func singleRecording(from recordings: [RecordedCall]) -> RecordedCall {
        guard let recording = recordings.first else {
            fatalError(
                "[TestDoubles] The recording closure did not invoke a protocol requirement. "
                    + "Call exactly one requirement inside `onCall` or `verify`. "
                    + "If this was a method declared only in a protocol extension, Swift dispatches "
                    + "it statically and TestDoubles cannot intercept it; declare it as a protocol "
                    + "requirement instead."
            )
        }
        guard recordings.count == 1 else {
            fatalError(
                "[TestDoubles] The recording closure invoked \(recordings.count) protocol requirements, "
                    + "but `onCall` and `verify` accept exactly one. Split them into separate operations; "
                    + "use `verifyInOrder` when checking an ordered sequence."
            )
        }
        return recording
    }
}

// MARK: - Verification

extension TestDouble {
    func verifyCallCount(
        _ expectedCounts: any RangeExpression<Int>,
        recording: RecordedCall,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        CallPattern<Void>(recorder: recorder, recording: recording).verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    func verifyCallCount(
        _ expectedCounts: PartialRangeFrom<Int>,
        within timeout: Duration,
        recording: RecordedCall,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) async {
        await CallPattern<Void>(recorder: recorder, recording: recording).verify(
            expectedCounts,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    func verifyCallCount(
        _ expectedCounts: PartialRangeFrom<Int>,
        within timeout: Duration,
        using clock: any StubClock,
        recording: RecordedCall,
        isolation: isolated (any Actor)? = #isolation,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) async {
        await CallPattern<Void>(recorder: recorder, recording: recording).verify(
            expectedCounts,
            within: timeout,
            using: clock,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    func verifyInOrder(
        recordings: [RecordedCall],
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        guard recordings.isEmpty == false else {
            reportIssue(
                "Ordered verification requires at least one invocation",
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
        guard let failure = recorder.orderedVerificationFailure(for: recordings) else {
            return
        }
        reportIssue(
            failure,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    func verifyExactlyInOrder(
        recordings: [RecordedCall],
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        guard recordings.isEmpty == false else {
            reportIssue(
                "Exact ordered verification requires at least one invocation",
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
            return
        }
        guard let failure = recorder.exactOrderedVerificationFailure(for: recordings) else {
            return
        }
        reportIssue(
            failure,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    func reportUnverifiedInteractions(
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        guard let diagnostic = recorder.unverifiedInteractionsDiagnostic() else {
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

    func reportUnusedRegistrations(
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        guard let diagnostic = recorder.unusedRegistrationsDiagnostic() else {
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
}

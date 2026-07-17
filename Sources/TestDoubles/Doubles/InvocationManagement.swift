extension Stub {
    /// Clears every recorded invocation while preserving configured behavior.
    ///
    /// Return sequences continue from their current position. Eventual
    /// verifications already waiting on this stub re-evaluate against the
    /// cleared invocation log.
    public func clearRecordedInvocations() {
        recorder.clearRecordedInvocations()
    }

    /// Reports every recorded invocation that has not been covered by a
    /// successful verification.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        reportUnverifiedInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension ManualStub {
    /// Clears every recorded invocation while preserving configured behavior.
    ///
    /// Return sequences continue from their current position. Eventual
    /// verifications already waiting on this stub re-evaluate against the
    /// cleared invocation log.
    public func clearRecordedInvocations() {
        recorder.clearRecordedInvocations()
    }

    /// Reports every recorded invocation that has not been covered by a
    /// successful verification.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        reportUnverifiedInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

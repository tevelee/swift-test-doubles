extension Stub {
    /// Clears every recorded invocation while preserving configured behavior.
    ///
    /// Behavior chains continue from their current position. Eventual
    /// verifications already waiting on this stub re-evaluate against the
    /// cleared invocation log.
    public func clearRecordedInvocations() {
        recorder.clearRecordedInvocations()
    }

    /// Removes every `when` registration while preserving recorded
    /// invocations.
    ///
    /// A later matching call behaves like a call to an unconfigured double:
    /// it halts with a diagnostic, or forwards to the target on a `Spy`.
    /// Calls already parked by a suspending behavior are unaffected; their
    /// behavior started before the clear.
    public func clearConfiguredBehaviors() {
        recorder.clearConfiguredBehaviors()
    }

    /// Restores the just-constructed state: removes every `when` registration
    /// and clears the invocation log, so the stub can be reconfigured from
    /// scratch, as between parameterized test cases.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
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

    /// Reports every `when` registration that no recorded call ever matched.
    ///
    /// An unused registration is usually stale setup, or a specific
    /// registration unreachable behind an earlier catch-all under
    /// first-match-wins. Call at the end of a test to catch both.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        reportUnusedRegistrations(
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
    /// Behavior chains continue from their current position. Eventual
    /// verifications already waiting on this stub re-evaluate against the
    /// cleared invocation log.
    public func clearRecordedInvocations() {
        recorder.clearRecordedInvocations()
    }

    /// Removes every `when` registration while preserving recorded
    /// invocations.
    ///
    /// A later matching call behaves like a call to an unconfigured double
    /// and halts with a diagnostic.
    public func clearConfiguredBehaviors() {
        recorder.clearConfiguredBehaviors()
    }

    /// Restores the just-constructed state by removing configured behavior
    /// and recorded invocations.
    ///
    /// Hand-written conformers should forward a protocol requirement named
    /// `reset` through ``CompiledStub/requirements`` so it cannot collide with
    /// this control operation.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
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

    /// Reports every `when` registration that no recorded call ever matched.
    ///
    /// An unused registration is usually stale setup, or a specific
    /// registration unreachable behind an earlier catch-all under
    /// first-match-wins. Call at the end of a test to catch both.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        reportUnusedRegistrations(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

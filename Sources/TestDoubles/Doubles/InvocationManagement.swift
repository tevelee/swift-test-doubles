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
    /// and halts with a diagnostic. Pair with `clearRecordedInvocations()`
    /// to restore the just-constructed state. There is deliberately no
    /// `reset()` on `ManualStub`: member names dispatch requirements here,
    /// and a concrete `reset` would shadow a protocol's own `reset`
    /// requirement.
    public func clearConfiguredBehaviors() {
        recorder.clearConfiguredBehaviors()
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

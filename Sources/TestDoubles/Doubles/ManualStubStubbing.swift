extension ManualStub {
    /// Describes a method or getter for behavior and interaction operations.
    public func when<Result>(_ call: (T) throws -> Result) -> CallPattern<Result> {
        let recording = recordInvocation(call)
        return CallPattern(recorder: recorder, recording: recording)
    }

    /// Describes a call whose result needs a valid value while recording.
    ///
    /// Use this overload for reference, existential, and other results for which
    /// a placeholder cannot be synthesized safely. The placeholder is returned
    /// only while capturing `call`; configured behavior still comes from the
    /// resulting builder.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (T) throws -> Result
    ) -> CallPattern<Result> {
        let recording = recordInvocation(returning: placeholder, call)
        return CallPattern(recorder: recorder, recording: recording)
    }

    /// Describes a direct property assignment.
    public func when(_ call: (inout T) throws -> Void) -> CallPattern<Void> {
        let recording = recordMutation(call)
        return CallPattern(recorder: recorder, recording: recording)
    }

    /// Describes an async method or getter for behavior and interaction operations.
    public func when<Result>(
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> CallPattern<Result> {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        return CallPattern(recorder: recorder, recording: recording)
    }

    /// Describes an async call whose result needs a valid value while recording.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> CallPattern<Result> {
        let recording = await recordAsyncInvocation(
            returning: placeholder,
            call,
            isolation: isolation
        )
        return CallPattern(recorder: recorder, recording: recording)
    }
}

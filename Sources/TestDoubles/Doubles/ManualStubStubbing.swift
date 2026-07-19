extension ManualStub {
    /// Stubs a method or getter, including throwing requirements.
    public func when<Result>(_ call: (T) throws -> Result) -> StubBuilder<Result> {
        let recording = recordInvocation(call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs a method or getter whose result needs a valid value while recording.
    ///
    /// Use this overload for reference, existential, and other results for which
    /// a placeholder cannot be synthesized safely. The placeholder is returned
    /// only while capturing `call`; configured behavior still comes from the
    /// resulting builder.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (T) throws -> Result
    ) -> StubBuilder<Result> {
        let recording = recordInvocation(returning: placeholder, call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs a direct property assignment.
    public func when(_ call: (inout T) throws -> Void) -> StubBuilder<Void> {
        let recording = recordMutation(call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs an async method or getter, including throwing requirements.
    public func when<Result>(
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result> {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs an async method or getter whose result needs a valid value while recording.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result> {
        let recording = await recordAsyncInvocation(
            returning: placeholder,
            call,
            isolation: isolation
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }
}

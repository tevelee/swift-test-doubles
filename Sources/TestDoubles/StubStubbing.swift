extension Stub {
    /// Stubs a method or getter, including throwing requirements.
    @discardableResult
    public func when<Result>(_ call: (P) throws -> Result) -> StubBuilder<Result> {
        let recording = record { _ = try! call(self()) }
        return builder(for: recording, returning: Result.self)
    }

    /// Stubs an async method or getter, including throwing requirements.
    @_disfavoredOverload
    @discardableResult
    public func when<Result>(
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result> {
        let recording = await recordAsync(isolation: isolation) {
            _ = try! await call(self())
        }
        return builder(for: recording, returning: Result.self)
    }

    private func builder<Result>(
        for recording: RecordedCall,
        returning resultType: Result.Type
    ) -> StubBuilder<Result> {
        if resultType == Void.self {
            recorder.addStub(
                method: recording.methodIndex,
                matchers: recording.resolvedMatchers,
                returnValue: { _ in () },
                isFallback: true
            )
        }
        return StubBuilder(recorder: recorder, recording: recording)
    }
    func recordAsync(
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async -> Void
    ) async -> RecordedCall {
        let (_, matchers) = await MatcherContext.withRecording(isolation: isolation) {
            recorder.mode = .capturing
            await block()
        }
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the async closure")
        }
        recorder.lastRecording = nil
        return recording
    }

    func record(_ block: () -> Void) -> RecordedCall {
        let (_, matchers) = MatcherContext.withRecording {
            recorder.mode = .capturing
            block()
        }
        if !matchers.isEmpty {
            recorder.lastRecording?.matchers = matchers
        }
        recorder.mode = .normal
        guard let recording = recorder.lastRecording else {
            fatalError("No method was called in the closure")
        }
        recorder.lastRecording = nil
        return recording
    }
}

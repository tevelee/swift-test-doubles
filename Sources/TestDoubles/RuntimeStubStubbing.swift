#if RUNTIME_STUB
extension RuntimeStub {
    /// Stub a method or getter.
    @discardableResult
    public func when<R>(_ call: (P) -> R) -> StubBuilder<R> {
        let recording = record { _ = call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a throwing method or getter.
    /// During recording, the thunk returns zero (never throws), so try! is safe.
    @discardableResult
    public func when<R>(_ call: (P) throws -> R) -> StubBuilder<R> {
        let recording = record { _ = try! call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) -> Void) -> StubBuilder<Void> {
        let recording = record { call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void throwing method — auto-registers.
    @discardableResult
    public func when(_ call: (P) throws -> Void) -> StubBuilder<Void> {
        let recording = record { try! call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = await call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing method.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async throws -> R) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = try! await call(self.callAsFunction()) }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) async -> Void) async -> StubBuilder<Void> {
        let recording = await recordAsync { await call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing void method — auto-registers.
    @discardableResult
    public func when(_ call: (P) async throws -> Void) async -> StubBuilder<Void> {
        let recording = await recordAsync { try! await call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub with a static value:
    /// `stub.when { $0.find(id: any()) } then: { "Alice" }`
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping () -> R) -> StubBuilder<R> {
        let builder = when(call)
        builder.returns(handler())
        return builder
    }

    /// Stub with dynamic args:
    /// `stub.when { $0.find(id: any()) } then: { args in "user_\(args[0])" }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping ([Any]) -> R) -> StubBuilder<R> {
        let builder = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { handler($0) })
        return builder
    }

    /// Throwing stub:
    /// `stub.when { try $0.read(path: any()) } then: { "content" }`
    /// `stub.when { try $0.read(path: any()) } then: { throw NotFoundError() }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping () throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers) { _ in try handler() }
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { _ in try! handler() })
        return builder
    }

    /// Throwing stub with dynamic args:
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping ([Any]) throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers, handler: handler)
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { try! handler($0) })
        return builder
    }

    /// Async stub:
    /// `await stub.when { try await $0.load(url: any()) } then: { "data" }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) async throws -> R, then handler: @escaping () throws -> R) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call)
        let matchers = builder.recording.matchers.isEmpty
            ? builder.recording.args.map { DescriptionMatcher(value: $0) }
            : builder.recording.matchers
        recorder.addThrowingStub(method: builder.recording.methodIndex, matchers: matchers) { _ in try handler() }
        recorder.addStub(method: builder.recording.methodIndex, matchers: matchers, returnValue: { _ in try! handler() })
        return builder
    }

    /// Stub a setter: `stub.when(setting: { $0.name = "x" })`
    @_disfavoredOverload
    @discardableResult
    public func when(setting call: (inout P) -> Void) -> StubBuilder<Void> {
        let recording = record {
            var mutable = self.callAsFunction()
            call(&mutable)
        }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in () })
        return StubBuilder(recorder: recorder, recording: recording)
    }

    func recordAsync(mode: StubRecorder.Mode = .recording, _ block: () async -> Void) async -> RecordedCall {
        recorder.activeMatchers = []
        let (_, matchers) = await MatcherContext.withRecording {
            recorder.mode = mode
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

    func record(mode: StubRecorder.Mode = .recording, _ block: () -> Void) -> RecordedCall {
        recorder.activeMatchers = []
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        let (_, matchers) = MatcherContext.withRecording {
            recorder.mode = mode
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
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        return recording
    }
}
#endif // RUNTIME_STUB

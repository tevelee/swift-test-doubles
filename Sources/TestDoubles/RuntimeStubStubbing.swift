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
        recorder.addStub(
            method: recording.methodIndex,
            matchers: matchers,
            returnValue: { _ in () },
            isFallback: true
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub a void throwing method — auto-registers.
    @discardableResult
    public func when(_ call: (P) throws -> Void) -> StubBuilder<Void> {
        let recording = record { try! call(self.callAsFunction()) }
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(
            method: recording.methodIndex,
            matchers: matchers,
            returnValue: { _ in () },
            isFallback: true
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async method. Void requirements are auto-registered.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = await call(self.callAsFunction()) }
        if R.self == Void.self {
            let matchers = recording.matchers.isEmpty
                ? recording.args.map { DescriptionMatcher(value: $0) }
                : recording.matchers
            recorder.addStub(
                method: recording.methodIndex,
                matchers: matchers,
                returnValue: { _ in () },
                isFallback: true
            )
        }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub an async throwing method. Void requirements are auto-registered.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async throws -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let recording = await recordAsync { _ = try! await call(self.callAsFunction()) }
        if R.self == Void.self {
            let matchers = recording.matchers.isEmpty
                ? recording.args.map { DescriptionMatcher(value: $0) }
                : recording.matchers
            recorder.addStub(
                method: recording.methodIndex,
                matchers: matchers,
                returnValue: { _ in () },
                isFallback: true
            )
        }
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stub with a static value:
    /// `stub.when { $0.find(id: any()) } then: { "Alice" }`
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping () -> R) -> StubBuilder<R> {
        let builder = when(call)
        return builder.then(handler)
    }

    /// Stub with dynamic args:
    /// `stub.when { $0.find(id: any()) } then: { args in "user_\(args[0])" }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) -> R, then handler: @escaping ([Any]) -> R) -> StubBuilder<R> {
        let builder = when(call)
        return builder.then(handler)
    }

    /// Throwing stub:
    /// `stub.when { try $0.read(path: any()) } then: { "content" }`
    /// `stub.when { try $0.read(path: any()) } then: { throw NotFoundError() }`
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping () throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        return builder.then(handler)
    }

    /// Throwing stub with dynamic args:
    @_disfavoredOverload
    @discardableResult
    public func when<R>(_ call: (P) throws -> R, then handler: @escaping ([Any]) throws -> R) -> StubBuilder<R> {
        let builder: StubBuilder<R> = when(call)
        return builder.then(handler)
    }

    /// Stub an async method with an immediate no-argument handler.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async -> R,
        then handler: @escaping () -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.then(handler)
    }

    /// Stub an async method with an immediate synchronous handler.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async -> R,
        then handler: @escaping ([Any]) -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.then(handler)
    }

    /// Stub an async throwing method with an immediate no-argument handler.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async throws -> R,
        then handler: @escaping () throws -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.then(handler)
    }

    /// Stub an async throwing method with an immediate synchronous handler.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async throws -> R,
        then handler: @escaping ([Any]) throws -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.then(handler)
    }

    /// Stub an async method with a handler that may suspend.
    ///
    /// The handler runs as part of the caller's task, preserving task-local
    /// values, priority, cancellation, and actor isolation.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async -> R,
        thenAsync handler: @escaping () async -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.thenAsync(handler)
    }

    /// Stub an async method with a suspending handler that receives its arguments.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async -> R,
        thenAsync handler: @escaping ([Any]) async -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.thenAsync(handler)
    }

    /// Stub an async throwing method with a handler that may suspend or throw.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async throws -> R,
        thenAsync handler: @escaping () async throws -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.thenAsync(handler)
    }

    /// Stub an async throwing method with a suspending, argument-aware handler.
    @_disfavoredOverload
    @discardableResult
    public func when<R>(
        _ call: (P) async throws -> R,
        thenAsync handler: @escaping ([Any]) async throws -> R,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<R> {
        let builder: StubBuilder<R> = await when(call, isolation: isolation)
        return builder.thenAsync(handler)
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
        recorder.addStub(
            method: recording.methodIndex,
            matchers: matchers,
            returnValue: { _ in () },
            isFallback: true
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    func recordAsync(
        mode: StubRecorder.Mode = .recording,
        isolation: isolated (any Actor)? = #isolation,
        _ block: () async -> Void
    ) async -> RecordedCall {
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        let (_, matchers) = await MatcherContext.withRecording(isolation: isolation) {
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
        if mode == .verifying {
            recorder.verificationRecordings = []
        }
        return recording
    }

    func record(mode: StubRecorder.Mode = .recording, _ block: () -> Void) -> RecordedCall {
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

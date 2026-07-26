extension StubBuilder where Result: Encodable & Sendable {
    /// Runs `handler` — typically a call to the real dependency a `Spy`
    /// forwards to — and records its result into `session` under `key`, in
    /// addition to returning it as this call's answer.
    ///
    /// ```swift
    /// let spy: Spy<any WeatherService> = .make(forwardingTo: live)
    /// let session = RecordingSession()
    /// spy.when { try await $0.currentConditions(for: any()) }
    ///     .thenRecord(as: "currentConditions", into: session) { city in
    ///         try await live.currentConditions(for: city)
    ///     }
    /// ```
    ///
    /// Only a successful result is captured; a thrown error still propagates
    /// to the caller but is not recorded. Replay the session's eventual
    /// ``InteractionFixture`` with ``thenReplay(as:from:)``. `Result` must be
    /// `Encodable` so it can be persisted as JSON.
    public func thenRecord<each Argument>(
        as key: String,
        into session: RecordingSession,
        calling handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            let result = try invokeTypedHandler(handler, with: arguments, method: methodName)
            session.recordSuccess(result, as: key)
            return result
        }
    }

    /// The async form of ``thenRecord(as:into:calling:)-62gmo``, for an async
    /// requirement forwarding to an async real dependency.
    public func thenRecord<each Argument>(
        as key: String,
        into session: RecordingSession,
        calling handler: @escaping (repeat each Argument) async throws -> Result
    ) {
        requireOrdinaryResult()
        addAsyncStubBehavior { arguments, methodName in
            let result = try await invokeTypedHandler(handler, with: arguments, method: methodName)
            session.recordSuccess(result, as: key)
            return result
        }
    }
}

extension StubBuilder where Result: Decodable {
    /// Configures fixed responses for this registration from `fixture`'s
    /// calls recorded under `key`, in recording order — exactly like
    /// `thenReturn(_:_:_:)` built from playback: the last recorded response
    /// repeats for every call after that.
    ///
    /// `key` must match the one passed to `thenRecord(as:into:calling:)` when
    /// the fixture was captured, with at least one recorded call; otherwise
    /// this halts with a diagnostic naming the missing key.
    public func thenReplay(as key: String, from fixture: InteractionFixture) {
        requireOrdinaryResult()
        let values = fixture.decodedResults(as: key, resultType: Result.self)
        guard let first = values.first else {
            fatalError(
                "[TestDoubles] Fixture has no recorded calls under '\(key)'. Record at least one call with thenRecord(as:into:calling:) before replaying it."
            )
        }
        for value in values {
            recorder.requireReturnValueMatchesRuntimeType(value, for: recording.methodIndex)
        }
        let answers: [(StubRecorder.QueuedAnswer, StubRecorder.RepeatCount)] =
            values.dropLast().map { (fixedAnswer(.success($0), after: nil), .exactly(1)) }
            + [(fixedAnswer(.success(values.last ?? first), after: nil), .unbounded)]
        _ = makeBehaviorChain(answers)
    }
}

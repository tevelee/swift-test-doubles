import Foundation

extension CallPattern where Result: Encodable & Sendable {
    /// Runs `handler` — typically a call to the real dependency a `Spy`
    /// forwards to — and records its result into `session` under `key`, in
    /// addition to returning it as this call's answer.
    ///
    /// ```swift
    /// let spy: Spy<any WeatherService> = .make(forwardingTo: live)
    /// let session = RecordingSession()
    /// spy.when { try await $0.currentConditions(for: Match.any()) }
    ///     .thenRecord(as: "currentConditions", into: session) { city in
    ///         try await live.currentConditions(for: city)
    ///     }
    /// ```
    ///
    /// A successful result is captured and any error propagates to the caller.
    /// Use `thenRecord(as:into:recordingErrorsAs:calling:)` when errors also
    /// belong in the fixture. Replay the session's eventual
    /// ``InteractionFixture`` with ``thenReplay(as:from:)``. `Result` must be
    /// `Encodable` so it can be persisted as JSON.
    @discardableResult
    public func thenRecord<each Argument>(
        as key: String,
        into session: RecordingSession,
        calling handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> CallInteractions {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            let result = try invokeTypedHandler(handler, with: arguments, method: methodName)
            session.recordSuccess(result, as: key)
            return result
        }
        return interactions
    }

    /// Records both a successful result and a caller-defined, Codable request
    /// value. Replay it with `thenReplay(as:from:matching:redacting:)` to ensure a
    /// fixture response is selected only for the matching input.
    @discardableResult
    public func thenRecord<Request: Encodable & Sendable, each Argument>(
        as key: String,
        into session: RecordingSession,
        recording request: @escaping @Sendable (repeat each Argument) -> Request,
        calling handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> CallInteractions {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            let result = try invokeTypedHandler(handler, with: arguments, method: methodName)
            let recordedRequest = invokeTypedHandler(
                request,
                with: arguments,
                method: methodName,
                context: "Fixture request"
            )
            session.recordSuccess(result, recording: recordedRequest, as: key)
            return result
        }
        return interactions
    }

    /// Records successful results and errors of `Failure` into `session`.
    ///
    /// Replay the fixture through ``thenReplay(as:from:throwing:)``. Errors
    /// outside `Failure` still propagate but fail closed rather than being
    /// silently serialized under the wrong error type.
    @discardableResult
    public func thenRecord<Failure: Error & Encodable & Sendable, each Argument>(
        as key: String,
        into session: RecordingSession,
        recordingErrorsAs _: Failure.Type,
        calling handler: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> CallInteractions {
        requireOrdinaryResult()
        addStubBehavior { arguments, methodName in
            do {
                let result = try invokeTypedHandler(handler, with: arguments, method: methodName)
                session.recordSuccess(result, as: key)
                return result
            } catch let error as Failure {
                session.recordFailure(error, as: key)
                throw error
            }
        }
        return interactions
    }

    /// Async counterpart to `thenRecord(as:into:recordingErrorsAs:calling:)`.
    @discardableResult
    public func thenRecord<Failure: Error & Encodable & Sendable, each Argument>(
        as key: String,
        into session: RecordingSession,
        recordingErrorsAs _: Failure.Type,
        calling handler: @escaping (repeat each Argument) async throws -> Result
    ) -> CallInteractions {
        requireOrdinaryResult()
        addAsyncStubBehavior { arguments, methodName in
            do {
                let result = try await invokeTypedHandler(handler, with: arguments, method: methodName)
                session.recordSuccess(result, as: key)
                return result
            } catch let error as Failure {
                session.recordFailure(error, as: key)
                throw error
            }
        }
        return interactions
    }

    /// The async form of ``thenRecord(as:into:calling:)-2d9h6``, for an async
    /// requirement forwarding to an async real dependency.
    @discardableResult
    public func thenRecord<each Argument>(
        as key: String,
        into session: RecordingSession,
        calling handler: @escaping (repeat each Argument) async throws -> Result
    ) -> CallInteractions {
        requireOrdinaryResult()
        addAsyncStubBehavior { arguments, methodName in
            let result = try await invokeTypedHandler(handler, with: arguments, method: methodName)
            session.recordSuccess(result, as: key)
            return result
        }
        return interactions
    }
}

extension CallPattern where Result: Decodable {
    /// Configures fixed responses for this registration from `fixture`'s
    /// calls recorded under `key`, in recording order — exactly like
    /// `thenReturn(_:_:_:)` built from playback: the last recorded response
    /// repeats for every call after that.
    ///
    /// `key` must match the one passed to `thenRecord(as:into:calling:)` when
    /// the fixture was captured, with at least one recorded call; otherwise
    /// this halts with a diagnostic naming the missing key.
    @discardableResult
    public func thenReplay(
        as key: String,
        from fixture: InteractionFixture
    ) -> CallInteractions {
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
        return interactions
    }

    /// Replays a fixture result selected by an encoded request value.
    ///
    /// Each distinct request advances through its own recorded responses and
    /// repeats its final response once exhausted. A request absent from the
    /// fixture fails closed instead of accidentally consuming another input's
    /// recording.
    @discardableResult
    public func thenReplay<Request: Encodable & Sendable, each Argument>(
        as key: String,
        from fixture: InteractionFixture,
        matching request: @escaping @Sendable (repeat each Argument) -> Request,
        redacting redactor: FixtureRedactor = .none
    ) -> CallInteractions where Result: Sendable {
        requireOrdinaryResult()
        let cursor = InteractionFixtureReplayCursor()
        let recorder = recorder
        let methodIndex = recording.methodIndex
        addStubBehavior { arguments, methodName in
            let currentRequest = invokeTypedHandler(
                request,
                with: arguments,
                method: methodName,
                context: "Fixture replay request"
            )
            let recorded = fixture.decodedResults(
                as: key,
                matching: currentRequest,
                redacting: redactor,
                resultType: Result.self
            )
            guard let value = cursor.next(for: recorded.requestData, in: recorded.values) else {
                fatalError(
                    "[TestDoubles] Fixture has no recorded response for '\(key)' and the supplied request."
                )
            }
            recorder.requireReturnValueMatchesRuntimeType(value, for: methodIndex)
            return value
        }
        return interactions
    }

    /// Replays successful results and recorded `Failure` values in fixture order.
    ///
    /// The recorded requirement must be able to throw `Failure`. For a
    /// typed-throws requirement, pass its declared error type.
    @discardableResult
    public func thenReplay<Failure: Error & Decodable & Sendable>(
        as key: String,
        from fixture: InteractionFixture,
        throwing _: Failure.Type
    ) -> CallInteractions where Result: Sendable {
        requireOrdinaryResult()
        let outcomes = fixture.decodedOutcomes(
            as: key,
            resultType: Result.self,
            failureType: Failure.self
        )
        guard outcomes.isEmpty == false else {
            fatalError("[TestDoubles] Fixture has no recorded calls under '\(key)'.")
        }
        let cursor = InteractionFixtureReplayCursor()
        let recorder = recorder
        let methodIndex = recording.methodIndex
        addStubBehavior { _, _ in
            guard let outcome = cursor.next(for: Data(), in: outcomes) else {
                fatalError("[TestDoubles] Fixture has no replayable outcome for '\(key)'.")
            }
            switch outcome {
                case .success(let value):
                    recorder.requireReturnValueMatchesRuntimeType(value, for: methodIndex)
                    return value
                case .failure(let error):
                    throw error
            }
        }
        return interactions
    }
}

private final class InteractionFixtureReplayCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var nextIndices: [Data: Int] = [:]

    func next<Value>(for requestData: Data, in values: [Value]) -> Value? {
        guard values.isEmpty == false else { return nil }
        return lock.withLock {
            let index = nextIndices[requestData, default: 0]
            nextIndices[requestData] = index + 1
            return values[Swift.min(index, values.count - 1)]
        }
    }
}

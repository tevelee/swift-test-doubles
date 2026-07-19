extension Stub {
    /// Configures a nonfailable initializer requirement.
    ///
    /// Swift cannot express the opened existential metatype as a generic closure
    /// parameter, so invoke the initializer through `type(of:)` inside `call`.
    public func when(initializer call: (P) throws -> P) -> StubInitializerBuilder {
        let recording = recordInvocation(call)
        requireInitializerRecording(recording, returnConvention: .selfType)
        return StubInitializerBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an async nonfailable initializer requirement.
    ///
    /// Swift cannot express the opened existential metatype as a generic closure
    /// parameter, so invoke the initializer through `type(of:)` inside `call`.
    public func when(
        initializer call: (P) async throws -> P,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubInitializerBuilder {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        requireInitializerRecording(recording, returnConvention: .selfType)
        return StubInitializerBuilder(recorder: recorder, recording: recording)
    }

    /// Configures a failable initializer requirement.
    ///
    /// Swift cannot express the opened existential metatype as a generic closure
    /// parameter, so invoke the initializer through `type(of:)` inside `call`.
    public func when(initializer call: (P) throws -> P?) -> StubFailableInitializerBuilder {
        let recording = recordInvocation(call)
        requireInitializerRecording(recording, returnConvention: .optionalSelf)
        return StubFailableInitializerBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an async failable initializer requirement.
    ///
    /// Swift cannot express the opened existential metatype as a generic closure
    /// parameter, so invoke the initializer through `type(of:)` inside `call`.
    public func when(
        initializer call: (P) async throws -> P?,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubFailableInitializerBuilder {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        requireInitializerRecording(recording, returnConvention: .optionalSelf)
        return StubFailableInitializerBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an instance or static method, or getter, that returns dynamic `Self`.
    ///
    /// The configured invocation returns a fresh generated value backed by
    /// this stub's runtime resources.
    public func when(returningSelf call: (P) throws -> P) -> StubSelfResultBuilder {
        let recording = recordInvocation(call)
        requireSelfResultRecording(recording)
        return StubSelfResultBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an async instance or static method, or getter, that returns dynamic `Self`.
    ///
    /// The configured invocation returns a fresh generated value backed by
    /// this stub's runtime resources.
    public func when(
        returningSelf call: (P) async throws -> P,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubSelfResultBuilder {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        requireSelfResultRecording(recording)
        return StubSelfResultBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an instance or static method, or getter, that returns optional dynamic `Self`.
    ///
    /// A matching invocation can return a fresh generated value backed by this
    /// stub's runtime resources or `nil`.
    public func when(
        returningOptionalSelf call: (P) throws -> P?
    ) -> StubOptionalSelfResultBuilder {
        let recording = recordInvocation(call)
        requireOptionalSelfResultRecording(recording)
        return StubOptionalSelfResultBuilder(recorder: recorder, recording: recording)
    }

    /// Configures an async method or getter that returns optional dynamic `Self`.
    ///
    /// A matching invocation can return a fresh generated value backed by this
    /// stub's runtime resources or `nil`.
    public func when(
        returningOptionalSelf call: (P) async throws -> P?,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubOptionalSelfResultBuilder {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        requireOptionalSelfResultRecording(recording)
        return StubOptionalSelfResultBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs an instance or static method, or getter, including throwing requirements.
    public func when<Result>(_ call: (P) throws -> Result) -> StubBuilder<Result> {
        let recording = recordInvocation(call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs a requirement whose result needs a valid value while recording.
    ///
    /// Use this overload for reference, existential, and other results for which
    /// the runtime cannot safely synthesize a recording placeholder. The
    /// placeholder is returned only while capturing `call`; configured behavior
    /// still comes from the resulting builder.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (P) throws -> Result
    ) -> StubBuilder<Result> {
        let recording = recordInvocation(returning: placeholder, call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs a direct property assignment.
    ///
    /// Compound assignment and `inout` access use Swift's `_modify` coroutine.
    /// Configure its ordinary getter and direct setter separately with `when`.
    public func when(_ call: (inout P) throws -> Void) -> StubBuilder<Void> {
        let recording = recordMutation(call)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs an async instance or static method, or getter, including throwing requirements.
    public func when<Result>(
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result> {
        let recording = await recordAsyncInvocation(call, isolation: isolation)
        return StubBuilder(recorder: recorder, recording: recording)
    }

    /// Stubs an async requirement whose result needs a valid value while recording.
    ///
    /// Use this overload for reference, existential, and other results for which
    /// the runtime cannot safely synthesize a recording placeholder. The
    /// placeholder is returned only while capturing `call`; configured behavior
    /// still comes from the resulting builder.
    public func when<Result>(
        returning placeholder: Result,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result> {
        let recording = await recordAsyncInvocation(
            returning: placeholder,
            call,
            isolation: isolation
        )
        return StubBuilder(recorder: recorder, recording: recording)
    }

    private func requireInitializerRecording(
        _ recording: RecordedCall,
        returnConvention: WitnessValueConvention
    ) {
        guard let method = recorder.runtimeMethod(for: recording.methodIndex) else {
            preconditionFailure("[TestDoubles] The recording closure must invoke a requirement.")
        }
        if method.kind != .initializer,
            method.returnConvention == .selfType
        {
            preconditionFailure(
                "[TestDoubles] Dynamic Self results use when(returningSelf:)."
            )
        }
        if method.kind != .initializer,
            method.returnConvention == .optionalSelf
        {
            preconditionFailure(
                "[TestDoubles] Optional dynamic Self results use when(returningOptionalSelf:)."
            )
        }
        guard method.kind == .initializer,
            method.returnConvention == returnConvention
        else {
            preconditionFailure(
                "[TestDoubles] The recording closure must invoke the matching initializer kind."
            )
        }
    }

    private func requireSelfResultRecording(_ recording: RecordedCall) {
        guard let method = recorder.runtimeMethod(for: recording.methodIndex),
            method.kind != .initializer,
            method.returnConvention == .selfType
        else {
            preconditionFailure(
                "[TestDoubles] when(returningSelf:) requires an instance or static method, or getter, "
                    + "that returns dynamic Self."
            )
        }
    }

    private func requireOptionalSelfResultRecording(_ recording: RecordedCall) {
        guard let method = recorder.runtimeMethod(for: recording.methodIndex),
            method.kind != .initializer,
            method.returnConvention == .optionalSelf
        else {
            preconditionFailure(
                "[TestDoubles] when(returningOptionalSelf:) requires an instance or static method, "
                    + "or getter, that returns optional dynamic Self."
            )
        }
    }
}

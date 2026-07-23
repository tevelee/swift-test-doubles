extension TestDouble {
    /// Binds each matching recorded invocation's arguments to the requested
    /// tuple shape, in call order. Components bind from the front, so a tuple
    /// narrower than the requirement reads a leading prefix; a component that
    /// does not exist or does not match its argument's type halts with the
    /// standard typed-argument diagnostic.
    func typedMatchingInvocationArguments<each Argument>(
        recording: RecordedCall
    ) -> [(repeat each Argument)] {
        recorder.verificationMatches(
            method: recording.methodIndex,
            matchers: recording.resolvedMatchers
        ).map { call in
            var index = 0
            func nextArgument<T>(_ type: T.Type) -> T {
                defer { index += 1 }
                return typedArgument(
                    type,
                    from: call.args,
                    at: index,
                    method: call.name,
                    context: "Typed invocation access"
                )
            }
            return (repeat nextArgument((each Argument).self))
        }
    }
}

extension Stub {
    /// Returns a human-readable, ordered log of every recorded invocation,
    /// one call per line, for debugging.
    ///
    /// When a `verify` fails the useful next question is what actually *did*
    /// get called; printing this answers it without dropping down to
    /// ``Stub/invocations(_:)`` and reconstructing the picture by hand. Each
    /// line weaves the recorded arguments back into the requirement's labels,
    /// so a call reads the way it was written at the call site:
    ///
    /// ```swift
    /// print(analytics.describeInteractions())
    /// // [TestDoubles] Recorded 3 interactions in order:
    /// //   #1  track(event: "add_to_cart", value: 30)
    /// //   #2  track(event: "add_to_cart", value: 12)
    /// //   #3  track(event: "purchase", value: 42)
    /// ```
    ///
    /// This is a query for diagnostics: it does not verify, consume configured
    /// behavior, or commit captors. Forwarded calls on a `Spy` are included,
    /// the same as any other recorded call.
    public func describeInteractions() -> String {
        recorder.interactionLog()
    }

    /// Returns the recorded arguments of matching invocations as typed
    /// tuples, in call order.
    ///
    /// Annotate the result to select the tuple shape. Components bind to the
    /// requirement's arguments from the front, and trailing arguments may be
    /// omitted:
    ///
    /// ```swift
    /// let events: [(String, Int)] = analytics.invocations {
    ///     $0.track(event: any(), value: any())
    /// }
    /// ```
    ///
    /// Matchers filter which invocations are included; use `any()` for every
    /// argument to include every call to the requirement. Reading invocations
    /// is a query: it does not verify, consume configured behavior, or commit
    /// captors. For asserting counts or order, prefer `verify` and
    /// `verifyInOrder`, whose failures carry full diagnostics.
    public func invocations<Result, each Argument>(
        _ call: (P) throws -> Result
    ) -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(recording: recordInvocation(call))
    }

    /// Returns matching invocation arguments for a requirement whose result
    /// needs a valid value while recording.
    ///
    /// Use this overload for reference, existential, and other results for
    /// which the runtime cannot safely synthesize a recording placeholder.
    public func invocations<Result, each Argument>(
        returning placeholder: Result,
        _ call: (P) throws -> Result
    ) -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: recordInvocation(returning: placeholder, call)
        )
    }

    /// Returns the recorded arguments of matching async invocations as typed
    /// tuples, in call order. See ``Stub/invocations(_:)`` for the binding
    /// and filtering contract.
    public func invocations<Result, each Argument>(
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: await recordAsyncInvocation(call, isolation: isolation)
        )
    }

    /// Returns matching async invocation arguments for a requirement whose
    /// result needs a valid value while recording.
    public func invocations<Result, each Argument>(
        returning placeholder: Result,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: await recordAsyncInvocation(
                returning: placeholder,
                call,
                isolation: isolation
            )
        )
    }
}

extension ManualStub {
    /// Returns a human-readable, ordered log of every recorded invocation,
    /// one call per line, for debugging. See
    /// ``Stub/describeInteractions()`` for the format and contract.
    public func describeInteractions() -> String {
        recorder.interactionLog()
    }

    /// Returns the recorded arguments of matching invocations as typed
    /// tuples, in call order. See ``Stub/invocations(_:)`` for the binding
    /// and filtering contract.
    public func invocations<Result, each Argument>(
        _ call: (T) throws -> Result
    ) -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(recording: recordInvocation(call))
    }

    /// Returns matching invocation arguments for a requirement whose result
    /// needs a valid value while recording.
    public func invocations<Result, each Argument>(
        returning placeholder: Result,
        _ call: (T) throws -> Result
    ) -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: recordInvocation(returning: placeholder, call)
        )
    }

    /// Returns the recorded arguments of matching async invocations as typed
    /// tuples, in call order. See ``Stub/invocations(_:)`` for the binding
    /// and filtering contract.
    public func invocations<Result, each Argument>(
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: await recordAsyncInvocation(call, isolation: isolation)
        )
    }

    /// Returns matching async invocation arguments for a requirement whose
    /// result needs a valid value while recording.
    public func invocations<Result, each Argument>(
        returning placeholder: Result,
        _ call: (T) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> [(repeat each Argument)] {
        typedMatchingInvocationArguments(
            recording: await recordAsyncInvocation(
                returning: placeholder,
                call,
                isolation: isolation
            )
        )
    }
}

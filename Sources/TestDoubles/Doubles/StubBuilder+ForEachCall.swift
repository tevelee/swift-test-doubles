extension StubBuilder {
    /// Handles each matching invocation with a running call count as the
    /// handler's first argument, ahead of the requirement's typed arguments.
    ///
    /// The count starts at 1 and increments once per matching invocation this
    /// registration serves, including the current one. It is the natural way
    /// to vary a response by attempt — fail the first two calls and then
    /// recover, say — without threading a counter through the test yourself:
    ///
    /// ```swift
    /// loader.when { try $0.loadFeed() }.thenForEachCall { attempt in
    ///     if attempt < 3 { throw URLError(.timedOut) }
    ///     return ["Hello, world"]
    /// }
    /// ```
    ///
    /// The count is scoped to this registration, so a call that matches a more
    /// specific registration does not advance a general fallback's count, the
    /// same as a behavior chain. A separate name from `then` keeps the leading
    /// count from being mistaken for the requirement's first argument under
    /// trailing-closure syntax.
    ///
    /// - Precondition: Handler arguments after the count match a leading prefix
    ///   of the requirement's arguments in type and order. Trailing arguments
    ///   may be omitted, down to a handler taking only the count. A handler
    ///   that throws at runtime requires a throwing requirement.
    public func thenForEachCall<each Argument>(
        _ handler: @escaping @Sendable (Int, repeat each Argument) throws -> Result
    ) {
        requireOrdinaryResult()
        let counter = InvocationCounter()
        addStubBehavior { arguments, methodName in
            try invokeCountingHandler(
                handler,
                count: counter.next(),
                with: arguments,
                method: methodName
            )
        }
    }

    /// Handles each matching async invocation with a running call count as the
    /// handler's first argument, ahead of the requirement's typed arguments.
    /// See ``StubBuilder/thenForEachCall(_:)-72ner`` for the counting contract;
    /// the requirement must be async.
    public func thenForEachCall<each Argument>(
        _ handler: @escaping (Int, repeat each Argument) async throws -> Result
    ) {
        requireOrdinaryResult()
        let counter = InvocationCounter()
        addAsyncStubBehavior { arguments, methodName in
            try await invokeCountingHandler(
                handler,
                count: counter.next(),
                with: arguments,
                method: methodName
            )
        }
    }
}

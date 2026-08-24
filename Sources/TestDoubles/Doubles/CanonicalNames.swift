extension Stub {
    /// Returns a generated protocol existential.
    public func makeValue() -> P {
        self()
    }

    /// Calls `operation` with a generated value and keeps its runtime
    /// resources alive for the operation's complete duration.
    public func withGeneratedValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withValue(operation)
    }

    /// Asynchronously calls `operation` with a generated value and keeps its
    /// runtime resources alive for the operation's complete duration.
    public func withGeneratedValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withValue(operation)
    }
}

extension Stub where P: Sendable {
    /// Returns a generated, sendable protocol existential.
    public func makeValue() -> P {
        self()
    }

    /// Calls `operation` with a generated, sendable value and keeps its
    /// runtime resources alive for the operation's complete duration.
    public func withGeneratedValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withValue(operation)
    }

    /// Asynchronously calls `operation` with a generated, sendable value and
    /// keeps its runtime resources alive for the operation's complete duration.
    public func withGeneratedValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withValue(operation)
    }
}

extension CompiledStub {
    /// Returns a generated conformer backed by this compiled stub.
    public func makeValue() -> T {
        self()
    }
}

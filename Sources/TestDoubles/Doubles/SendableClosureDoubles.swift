/// A synchronous closure double whose input and result cross concurrency
/// domains safely.
///
/// Use ``ClosureDouble/sendableFunction`` when injecting the controlled
/// closure so Swift checks every capture at the `@Sendable` boundary.
public typealias SendableClosureDouble<Input, Result> =
    ClosureDouble<Input, Result>
where Input: Sendable, Result: Sendable

/// A synchronous throwing closure double with a checked `@Sendable` function.
public typealias SendableThrowingClosureDouble<Input, Result> =
    ThrowingClosureDouble<Input, Result>
where Input: Sendable, Result: Sendable

/// An asynchronous closure double with a checked `@Sendable` function.
public typealias SendableAsyncClosureDouble<Input, Result> =
    AsyncClosureDouble<Input, Result>
where Input: Sendable, Result: Sendable

/// An asynchronous throwing closure double with a checked `@Sendable`
/// function.
public typealias SendableAsyncThrowingClosureDouble<Input, Result> =
    AsyncThrowingClosureDouble<Input, Result>
where Input: Sendable, Result: Sendable

extension ClosureDouble where Input: Sendable, Result: Sendable {
    /// A concurrency-safe closure value whose captures are checked by Swift.
    public var sendableFunction: @Sendable (Input) -> Result {
        { input in self(input) }
    }
}

extension ThrowingClosureDouble where Input: Sendable, Result: Sendable {
    /// A concurrency-safe throwing closure whose captures are checked by
    /// Swift.
    public var sendableFunction: @Sendable (Input) throws -> Result {
        { input in try self(input) }
    }
}

extension AsyncClosureDouble where Input: Sendable, Result: Sendable {
    /// A concurrency-safe asynchronous closure whose captures are checked by
    /// Swift.
    public var sendableFunction: @Sendable (Input) async -> Result {
        { input in await self(input) }
    }
}

extension AsyncThrowingClosureDouble where Input: Sendable, Result: Sendable {
    /// A concurrency-safe asynchronous throwing closure whose captures are
    /// checked by Swift.
    public var sendableFunction: @Sendable (Input) async throws -> Result {
        { input in try await self(input) }
    }
}

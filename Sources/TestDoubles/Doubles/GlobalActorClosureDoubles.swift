/// A closure double with a checked `@MainActor` injection view.
public typealias MainActorClosureDouble<
    Input: Sendable,
    Result: Sendable
> = ClosureDouble<Input, Result>

/// A throwing closure double with a checked `@MainActor` injection view.
public typealias MainActorThrowingClosureDouble<
    Input: Sendable,
    Result: Sendable
> = ThrowingClosureDouble<Input, Result>

/// An asynchronous closure double with a checked `@MainActor` injection view.
public typealias MainActorAsyncClosureDouble<
    Input: Sendable,
    Result: Sendable
> = AsyncClosureDouble<Input, Result>

/// An asynchronous throwing closure double with a checked `@MainActor` view.
public typealias MainActorAsyncThrowingClosureDouble<
    Input: Sendable,
    Result: Sendable
> = AsyncThrowingClosureDouble<Input, Result>

/// A typed-throws closure double with a checked `@MainActor` injection view.
public typealias MainActorTypedThrowingClosureDouble<
    Input: Sendable,
    Result: Sendable,
    Failure: Error
> = TypedThrowingClosureDouble<Input, Result, Failure>

/// An asynchronous typed-throws closure double with a checked `@MainActor`
/// injection view.
public typealias MainActorAsyncTypedThrowingClosureDouble<
    Input: Sendable,
    Result: Sendable,
    Failure: Error
> = AsyncTypedThrowingClosureDouble<Input, Result, Failure>

extension ClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) -> Result {
        { @MainActor input in self(input) }
    }
}

extension ThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated throwing closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) throws -> Result {
        { @MainActor input in try self(input) }
    }
}

extension AsyncClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated asynchronous closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) async -> Result {
        { @MainActor input in await self(input) }
    }
}

extension AsyncThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated asynchronous throwing closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) async throws -> Result {
        { @MainActor input in try await self(input) }
    }
}

extension TypedThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated typed-throws closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) throws(Failure) -> Result {
        { @MainActor input throws(Failure) in try self(input) }
    }
}

extension AsyncTypedThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked main-actor-isolated asynchronous typed-throws closure value.
    public var mainActorFunction: @MainActor @Sendable (Input) async throws(Failure) -> Result {
        {
            @MainActor input throws(Failure) in
            try await self(input)
        }
    }
}

public enum FixtureClientFailure: Error, Equatable {
    case rejected
}

public typealias FixtureClientLookup =
    @Sendable (Int, String, Bool) async -> String

public typealias FixtureClientPing = @Sendable () -> Bool

public typealias FixtureClientParse =
    @Sendable (String, Int, Bool, Double) throws -> Int

public typealias FixtureClientTransform<Value> =
    @Sendable (Value, Int) -> Value

public typealias FixtureClientSave =
    @Sendable (Int) throws(FixtureClientFailure) -> String

public typealias FixtureClientAsyncSave =
    @Sendable (Int, String) async throws(FixtureClientFailure) -> String

public typealias FixtureClientLegacy = (String) async throws -> Int

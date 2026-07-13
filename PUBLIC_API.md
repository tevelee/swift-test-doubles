# Public API snapshot

This is the intentional source-level API for the first TestDoubles release.
It is a compact, human-reviewed projection of the public Swift symbol graph;
runtime implementation types are deliberately absent.

```swift
public final class Stub<P>: @unchecked Sendable {
    public convenience init(_ requirements: Requirement...) throws
    public func callAsFunction() -> P

    public struct Requirement: Sendable {
        public static func method<each Argument, Result>(
            _ arguments: repeat (each Argument).Type,
            returning result: Result.Type,
            isThrowing: Bool = false,
            isAsync: Bool = false
        ) -> Self

        public static func getter<Value>(
            _ value: Value.Type,
            isThrowing: Bool = false,
            isAsync: Bool = false
        ) -> Self
    }

    public enum CallCount: Sendable {
        case atLeastOnce
        case exactly(Int)
        case never
    }

    public func when<Result>(_ call: (P) throws -> Result) -> StubBuilder<Result>
    public func when<Result>(
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async -> StubBuilder<Result>

    public func verify<Result>(
        _ expectedCount: CallCount = .atLeastOnce,
        _ call: (P) throws -> Result
    )
    public func verify<Result>(
        _ expectedCount: CallCount = .atLeastOnce,
        _ call: (P) async throws -> Result,
        isolation: isolated (any Actor)? = #isolation
    ) async
}

public struct StubBuilder<Result> {
    public func returns(_ value: Result)
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) throws -> Result
    )
    public func then<each Argument>(
        _ handler: @escaping (repeat each Argument) async throws -> Result
    )
}

public func any<T>() -> T
public func equal<T: Equatable>(_ value: T) -> T
public func matching<T>(
    description: String = "predicate",
    where predicate: @escaping (T) -> Bool
) -> T

public final class ArgumentCaptor<T> {
    public init()
    public var values: [T] { get }
    public var first: T? { get }
    public var last: T? { get }
    public func capture() -> T
    public func reset()
}

public enum StubError: Error, Sendable, CustomStringConvertible {
    case typeIsNotProtocol(typeDescription: String)
    case unsupportedProtocolComposition(typeDescription: String)
    case unsupportedProtocolShape(protocolName: String, reason: String)
    case noConformanceFound(protocolName: String)
    case requirementCountMismatch(
        protocolName: String,
        expected: Int,
        actual: Int
    )
    case requirementKindMismatch(
        protocolName: String,
        requirementIndex: Int,
        expected: String,
        actual: String
    )
    case signatureDiscoveryFailed(
        protocolName: String,
        requirementIndex: Int,
        details: String
    )
    case trampolineAllocationFailed(requirementIndex: Int)
    case unsupportedFunctionValue(protocolName: String, requirementIndex: Int)
    case unsupportedTypeKind(typeName: String)

    public var description: String { get }
}
```

The snapshot is updated only when a public API change is intentional. Before a
release, compare it with:

```sh
xcrun swift package dump-symbol-graph \
  --minimum-access-level public \
  --skip-synthesized-members
```

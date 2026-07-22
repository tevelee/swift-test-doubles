public typealias ExternalManagedClosure = (String) -> String
public typealias ExternalThrowingClosure = @Sendable (Int) throws -> String
public typealias ExternalAsyncClosure = @Sendable (Int) async -> String
public typealias ExternalAsyncThrowingClosure =
    @Sendable (String) async throws -> Int
public typealias ExternalAsyncMixedClosure =
    @Sendable (Int, Double, Bool, String) async throws -> ExternalNullaryAggregate
public typealias ExternalInoutClosure = @Sendable (inout Int) -> Void
public typealias ExternalConsumingClosure =
    @Sendable (consuming String) -> String
public typealias ExternalBorrowingClosure =
    @Sendable (borrowing String) -> String
public typealias ExternalVariadicClosure = @Sendable (Int...) -> Int
public typealias ExternalAutoclosureClosure =
    @Sendable (@autoclosure () -> Int) -> Int
public typealias ExternalNestedClosure =
    @Sendable (@escaping ExternalTransform) -> ExternalTransform

/// Compiled separately from TestDoubles so these signatures exercise the
/// runtime-only path without protocol source access or declaration macros.
public protocol ExternalAdvancedClosureService {
    func managed(
        _ closure: @escaping ExternalManagedClosure
    ) -> ExternalManagedClosure
    func throwing(
        _ closure: @escaping ExternalThrowingClosure
    ) -> ExternalThrowingClosure
    func asynchronous(
        _ closure: @escaping ExternalAsyncClosure
    ) -> ExternalAsyncClosure
    func asynchronousThrowing(
        _ closure: @escaping ExternalAsyncThrowingClosure
    ) -> ExternalAsyncThrowingClosure
    func asynchronousMixed(
        _ closure: @escaping ExternalAsyncMixedClosure
    ) -> ExternalAsyncMixedClosure
    func inoutValue(
        _ closure: @escaping ExternalInoutClosure
    ) -> ExternalInoutClosure
    func consuming(
        _ closure: @escaping ExternalConsumingClosure
    ) -> ExternalConsumingClosure
    func borrowing(
        _ closure: @escaping ExternalBorrowingClosure
    ) -> ExternalBorrowingClosure
    func variadic(
        _ closure: @escaping ExternalVariadicClosure
    ) -> ExternalVariadicClosure
    func autoclosure(
        _ closure: @escaping ExternalAutoclosureClosure
    ) -> ExternalAutoclosureClosure
    func nested(
        _ closure: @escaping ExternalNestedClosure
    ) -> ExternalNestedClosure
    func asynchronousRequirement(
        _ closure: @escaping ExternalManagedClosure
    ) async -> ExternalManagedClosure
    func asyncThrowingRequirement(
        _ closure: @escaping ExternalThrowingClosure
    ) async throws -> ExternalThrowingClosure
    func invokeAsyncClosure(
        _ closure: @escaping ExternalAsyncClosure,
        value: Int
    ) async -> String
    func invokeAsyncThrowingClosure(
        _ closure: @escaping ExternalAsyncThrowingClosure,
        value: String
    ) async throws -> Int
}

public struct RealExternalAdvancedClosureService:
    ExternalAdvancedClosureService
{
    public init() {}

    public func managed(
        _ closure: @escaping ExternalManagedClosure
    ) -> ExternalManagedClosure { closure }

    public func throwing(
        _ closure: @escaping ExternalThrowingClosure
    ) -> ExternalThrowingClosure { closure }

    public func asynchronous(
        _ closure: @escaping ExternalAsyncClosure
    ) -> ExternalAsyncClosure { closure }

    public func asynchronousThrowing(
        _ closure: @escaping ExternalAsyncThrowingClosure
    ) -> ExternalAsyncThrowingClosure { closure }

    public func asynchronousMixed(
        _ closure: @escaping ExternalAsyncMixedClosure
    ) -> ExternalAsyncMixedClosure { closure }

    public func inoutValue(
        _ closure: @escaping ExternalInoutClosure
    ) -> ExternalInoutClosure { closure }

    public func consuming(
        _ closure: @escaping ExternalConsumingClosure
    ) -> ExternalConsumingClosure { closure }

    public func borrowing(
        _ closure: @escaping ExternalBorrowingClosure
    ) -> ExternalBorrowingClosure { closure }

    public func variadic(
        _ closure: @escaping ExternalVariadicClosure
    ) -> ExternalVariadicClosure { closure }

    public func autoclosure(
        _ closure: @escaping ExternalAutoclosureClosure
    ) -> ExternalAutoclosureClosure { closure }

    public func nested(
        _ closure: @escaping ExternalNestedClosure
    ) -> ExternalNestedClosure { closure }

    public func asynchronousRequirement(
        _ closure: @escaping ExternalManagedClosure
    ) async -> ExternalManagedClosure { closure }

    public func asyncThrowingRequirement(
        _ closure: @escaping ExternalThrowingClosure
    ) async throws -> ExternalThrowingClosure { closure }

    public func invokeAsyncClosure(
        _ closure: @escaping ExternalAsyncClosure,
        value: Int
    ) async -> String {
        await closure(value)
    }

    public func invokeAsyncThrowingClosure(
        _ closure: @escaping ExternalAsyncThrowingClosure,
        value: String
    ) async throws -> Int {
        try await closure(value)
    }

}

public struct ExternalMoveOnlyValue: ~Copyable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

public typealias ExternalMoveOnlyClosure =
    @Sendable (consuming ExternalMoveOnlyValue) -> Int

public protocol ExternalMoveOnlyClosureService {
    func transform(
        _ closure: @escaping ExternalMoveOnlyClosure
    ) -> ExternalMoveOnlyClosure
}

public struct RealExternalMoveOnlyClosureService:
    ExternalMoveOnlyClosureService
{
    public init() {}

    public func transform(
        _ closure: @escaping ExternalMoveOnlyClosure
    ) -> ExternalMoveOnlyClosure { closure }
}

public protocol ExternalNonescapingClosureService {
    func apply(_ closure: ExternalManagedClosure) -> String
}

public struct RealExternalNonescapingClosureService:
    ExternalNonescapingClosureService
{
    public init() {}

    public func apply(_ closure: ExternalManagedClosure) -> String {
        closure("value")
    }
}

public enum ExternalClosureError: Error, Equatable {
    case failed
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalTypedThrowingClosure =
    @Sendable (Int) throws(ExternalClosureError) -> String
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalAsyncTypedThrowingClosure =
    @Sendable (Int) async throws(ExternalClosureError) -> String
@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public typealias ExternalIsolatedClosure =
    @isolated(any) @Sendable (Int) async -> String
public typealias ExternalMainActorClosure =
    @MainActor @Sendable (Int) -> String
// swift-format-ignore
public typealias ExternalNonsendingClosure =
    nonisolated(nonsending) @Sendable (Int) async -> String
public typealias ExternalSendingClosure =
    @Sendable (sending String) -> sending String

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public protocol ExternalExtendedClosureService {
    func typedThrowing(
        _ closure: @escaping ExternalTypedThrowingClosure
    ) -> ExternalTypedThrowingClosure
    func asyncTypedThrowing(
        _ closure: @escaping ExternalAsyncTypedThrowingClosure
    ) -> ExternalAsyncTypedThrowingClosure
    func isolated(
        _ closure: @escaping ExternalIsolatedClosure
    ) -> ExternalIsolatedClosure
    func mainActor(
        _ closure: @escaping ExternalMainActorClosure
    ) -> ExternalMainActorClosure
    func nonsending(
        _ closure: @escaping ExternalNonsendingClosure
    ) -> ExternalNonsendingClosure
    func sending(
        _ closure: @escaping ExternalSendingClosure
    ) -> ExternalSendingClosure
}

@available(macOS 15, iOS 18, macCatalyst 18, tvOS 18, visionOS 2, watchOS 11, *)
public struct RealExternalExtendedClosureService:
    ExternalExtendedClosureService
{
    public init() {}

    public func typedThrowing(
        _ closure: @escaping ExternalTypedThrowingClosure
    ) -> ExternalTypedThrowingClosure { closure }

    public func asyncTypedThrowing(
        _ closure: @escaping ExternalAsyncTypedThrowingClosure
    ) -> ExternalAsyncTypedThrowingClosure { closure }

    public func isolated(
        _ closure: @escaping ExternalIsolatedClosure
    ) -> ExternalIsolatedClosure { closure }

    public func mainActor(
        _ closure: @escaping ExternalMainActorClosure
    ) -> ExternalMainActorClosure { closure }

    public func nonsending(
        _ closure: @escaping ExternalNonsendingClosure
    ) -> ExternalNonsendingClosure { closure }

    public func sending(
        _ closure: @escaping ExternalSendingClosure
    ) -> ExternalSendingClosure { closure }
}

/// A configurable closure double with a statically typed error channel.
///
/// `TypedThrowingClosureDouble<Input, Result, Failure>` represents
/// `(Input) throws(Failure) -> Result`. Registration and observation use the
/// same ``ThrowingClosureCallPattern`` surface as untyped throwing closure
/// doubles, while invocation rejects a configured error that is not `Failure`.
public final class TypedThrowingClosureDouble<
    Input,
    Result,
    Failure: Error
> {
    /// The precise typed-throws closure represented by this double.
    public typealias Function = (Input) throws(Failure) -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed behavior used to calculate a result.
    public typealias Handler =
        @Sendable (Input) throws(Failure) -> Result

    private let base: ThrowingClosureDouble<Input, Result>

    /// Creates an empty typed-throws closure double.
    public init() {
        base = ThrowingClosureDouble()
    }

    /// Creates a typed-throws closure spy that delegates unmatched inputs.
    public init(
        forwardingTo target:
            @escaping @Sendable (Input) throws(Failure) -> Result
    ) {
        base = ThrowingClosureDouble(
            forwardingTo: { input in
                try target(input)
            }
        )
    }

    /// The typed-throws closure value ready to inject.
    public var function: Function {
        { input throws(Failure) in
            try self(input)
        }
    }

    /// Invokes and records the double.
    public func callAsFunction(
        _ input: Input
    ) throws(Failure) -> Result {
        do {
            return try base(input)
        } catch let failure as Failure {
            throw failure
        } catch {
            failTypedClosureErrorMismatch(
                expected: Failure.self,
                actual: error
            )
        }
    }

    /// Assigns a diagnostic name.
    @discardableResult
    public func named(_ name: String) -> Self {
        base.named(name)
        return self
    }

    /// Starts a behavior registration selected by `matcher`.
    public func when(
        _ matcher: @escaping Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result> {
        base.when(
            matcher,
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result> {
        base.whenAny(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// A whole-double view of recorded invocations.
    public var history: InteractionHistory { base.history }

    /// Every recorded input, in call order.
    public var invocations: [Input] { base.invocations }

    /// Reports registrations that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        base.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behaviors.
    public func clearRecordedInvocations() {
        base.clearRecordedInvocations()
    }

    /// Clears configured behaviors while preserving calls.
    public func clearConfiguredBehaviors() {
        base.clearConfiguredBehaviors()
    }

    /// Clears configured behaviors and calls.
    public func reset() {
        base.reset()
    }
}

extension TypedThrowingClosureDouble where Input: Equatable {
    /// Starts a registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result> {
        base.when(
            equal: value,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension TypedThrowingClosureDouble: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

extension TypedThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked `@Sendable` typed-throws closure value.
    public var sendableFunction: @Sendable (Input) throws(Failure) -> Result {
        { input throws(Failure) in
            try self(input)
        }
    }
}

/// An asynchronous closure double with a statically typed error channel.
public final class AsyncTypedThrowingClosureDouble<
    Input,
    Result,
    Failure: Error
> {
    /// The precise asynchronous typed-throws closure represented by this
    /// double.
    public typealias Function =
        (Input) async throws(Failure) -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed asynchronous behavior used to calculate a result.
    public typealias Handler =
        (Input) async throws(Failure) -> Result

    private let base: AsyncThrowingClosureDouble<Input, Result>

    /// Creates an empty asynchronous typed-throws closure double.
    public init() {
        base = AsyncThrowingClosureDouble()
    }

    /// Creates an asynchronous typed-throws closure spy.
    public init(
        forwardingTo target:
            @escaping @Sendable (Input) async throws(Failure) -> Result
    ) {
        base = AsyncThrowingClosureDouble(
            forwardingTo: { input in
                try await target(input)
            }
        )
    }

    /// The asynchronous typed-throws closure ready to inject.
    public var function: Function {
        { input throws(Failure) in
            try await self(input)
        }
    }

    /// Invokes and records the double.
    public func callAsFunction(
        _ input: Input
    ) async throws(Failure) -> Result {
        do {
            return try await base(input)
        } catch let failure as Failure {
            throw failure
        } catch {
            failTypedClosureErrorMismatch(
                expected: Failure.self,
                actual: error
            )
        }
    }

    /// Assigns a diagnostic name.
    @discardableResult
    public func named(_ name: String) -> Self {
        base.named(name)
        return self
    }

    /// Starts a behavior registration selected by `matcher`.
    public func when(
        _ matcher: @escaping Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result> {
        base.when(
            matcher,
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result> {
        base.whenAny(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// A whole-double view of recorded invocations.
    public var history: InteractionHistory { base.history }

    /// Every recorded input, in call order.
    public var invocations: [Input] { base.invocations }

    /// Reports registrations that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        base.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behaviors.
    public func clearRecordedInvocations() {
        base.clearRecordedInvocations()
    }

    /// Clears configured behaviors while preserving calls.
    public func clearConfiguredBehaviors() {
        base.clearConfiguredBehaviors()
    }

    /// Clears configured behaviors and calls.
    public func reset() {
        base.reset()
    }
}

extension AsyncTypedThrowingClosureDouble where Input: Equatable {
    /// Starts a registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result> {
        base.when(
            equal: value,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension AsyncTypedThrowingClosureDouble: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

extension AsyncTypedThrowingClosureDouble
where Input: Sendable, Result: Sendable {
    /// A checked `@Sendable` asynchronous typed-throws closure.
    public var sendableFunction: @Sendable (Input) async throws(Failure) -> Result {
        { input throws(Failure) in
            try await self(input)
        }
    }
}

/// A typed-throws closure double configured with a live fallback.
public typealias TypedThrowingClosureSpy<Input, Result, Failure: Error> =
    TypedThrowingClosureDouble<Input, Result, Failure>

/// An asynchronous typed-throws closure double configured with a live
/// fallback.
public typealias AsyncTypedThrowingClosureSpy<
    Input,
    Result,
    Failure: Error
> = AsyncTypedThrowingClosureDouble<Input, Result, Failure>

private func failTypedClosureErrorMismatch<Failure: Error>(
    expected: Failure.Type,
    actual: any Error
) -> Never {
    fatalError(
        "[TestDoubles] Typed closure handler error mismatch: expected "
            + "\(expected), got \(type(of: actual)). Configure a \(expected) "
            + "error or use an untyped throwing closure double."
    )
}

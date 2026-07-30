private struct EffectfulClosureDoubleConformer<Input, Result>: ManualStubConformer {
    let stub: ManualStub<Self>
}

private enum ClosureEffects {
    case throwing
    case async
    case asyncThrowing

    var isAsync: Bool {
        switch self {
            case .throwing: false
            case .async, .asyncThrowing: true
        }
    }

    var isThrowing: Bool {
        switch self {
            case .async: false
            case .throwing, .asyncThrowing: true
        }
    }
}

private final class EffectfulClosureDoubleStorage<Input, Result> {
    let stub: ManualStub<EffectfulClosureDoubleConformer<Input, Result>>
    let effects: ClosureEffects

    init(
        effects: ClosureEffects,
        allowsForwardingFallback: Bool = false
    ) {
        stub = ManualStub(
            materializing: { EffectfulClosureDoubleConformer(stub: $0) },
            allowsForwardingFallback: allowsForwardingFallback
        )
        self.effects = effects
    }

    private var route: ManualMethodRouteIdentity {
        .typed(
            ManualRouteID(
                "callAsFunction(_:)",
                argumentTypeIDs: [ObjectIdentifier(Input.self)]
            )
        )
    }

    func callThrowing(_ input: Input) throws -> Result {
        try stub.dispatchThrowingMethod(route: route, args: [input])
    }

    func callThrowing(
        _ input: Input,
        forwardingTo fallback: @escaping () throws -> Result
    ) throws -> Result {
        let method = stub.internMethod(
            route: route,
            returnType: Result.self,
            isAsync: false,
            isThrowing: true
        )
        return try stub.dispatchThrowingValue(
            method: method,
            args: [input],
            forwardingTo: fallback
        )
    }

    func callAsync(_ input: Input) async -> Result {
        await stub.dispatchAsyncMethod(route: route, args: [input])
    }

    func callAsync(
        _ input: Input,
        forwardingTo fallback: () async -> Result
    ) async -> Result {
        let method = stub.internMethod(
            route: route,
            returnType: Result.self,
            isAsync: true,
            isThrowing: false
        )
        return await stub.dispatchAsyncValue(
            method: method,
            args: [input],
            forwardingTo: fallback
        )
    }

    func callAsyncThrowing(_ input: Input) async throws -> Result {
        try await stub.dispatchAsyncThrowingMethod(route: route, args: [input])
    }

    func callAsyncThrowing(
        _ input: Input,
        forwardingTo fallback: () async throws -> Result
    ) async throws -> Result {
        let method = stub.internMethod(
            route: route,
            returnType: Result.self,
            isAsync: true,
            isThrowing: true
        )
        return try await stub.dispatchAsyncThrowingValue(
            method: method,
            args: [input],
            forwardingTo: fallback
        )
    }

    func pattern(
        matching matcher: ParameterMatcher,
        location: StubSourceLocation? = nil
    ) -> CallPattern<Result> {
        let method = stub.recorder.internManualMethod(
            route: route,
            kind: .method,
            returnType: Result.self,
            isAsync: effects.isAsync,
            isThrowing: effects.isThrowing
        )
        let recording = RecordedCall(
            methodIndex: method.index,
            name: method.name,
            args: [],
            matchers: [matcher]
        ).taggingRegistrationLocation(location)
        return CallPattern(recorder: stub.recorder, recording: recording)
    }
}

/// A configurable, recordable double for an injected synchronous throwing
/// unary closure.
///
/// The `when → then → verify` model is the same as ``ClosureDouble``, while
/// ``ThrowingClosureCallPattern`` adds throwing handlers and fixed errors.
public final class ThrowingClosureDouble<Input, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (Input) throws -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed throwing behavior used to calculate a result.
    public typealias Handler = @Sendable (Input) throws -> Result

    private let storage: EffectfulClosureDoubleStorage<Input, Result>
    private let forwardingTarget: (@Sendable (Input) throws -> Result)?

    /// Creates an empty closure double. Calls require a matching behavior.
    public init() {
        storage = EffectfulClosureDoubleStorage(
            effects: .throwing
        )
        forwardingTarget = nil
    }

    /// Creates a throwing closure spy that delegates unmatched inputs.
    public init(
        forwardingTo target: @escaping @Sendable (Input) throws -> Result
    ) {
        storage = EffectfulClosureDoubleStorage(
            effects: .throwing,
            allowsForwardingFallback: true
        )
        forwardingTarget = target
    }

    /// The ordinary closure value, ready to inject into the subject under test.
    public var function: Function {
        { input in try self(input) }
    }

    /// Invokes and records the double.
    public func callAsFunction(_ input: Input) throws -> Result {
        guard let forwardingTarget else {
            return try storage.callThrowing(input)
        }
        return try storage.callThrowing(
            input,
            forwardingTo: {
                try forwardingTarget(input)
            }
        )
    }

    /// Assigns a name used in strict-scope and interaction diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        storage.stub.named(name)
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
        ThrowingClosureCallPattern(
            base: pattern(
                matching: PredicateMatcher(description: description, predicate: matcher),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result> {
        ThrowingClosureCallPattern(
            base: pattern(
                matching: AnyMatcher(),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// A whole-double view of every recorded invocation.
    public var history: InteractionHistory {
        storage.stub.history
    }

    /// Every recorded input, in call order.
    public var invocations: [Input] {
        pattern(matching: AnyMatcher()).arguments()
    }

    /// Reports every behavior registration that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.stub.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior and chain position.
    public func clearRecordedInvocations() {
        storage.stub.clearRecordedInvocations()
    }

    /// Clears configured behavior while preserving recorded calls.
    public func clearConfiguredBehaviors() {
        storage.stub.clearConfiguredBehaviors()
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
    }

    private func pattern(
        matching matcher: ParameterMatcher,
        location: StubSourceLocation? = nil
    ) -> CallPattern<Result> {
        storage.pattern(matching: matcher, location: location)
    }
}

/// A configurable, recordable double for an injected asynchronous
/// non-throwing unary closure.
///
/// ``AsyncClosureCallPattern`` offers both immediate and asynchronous computed
/// handlers, delayed results, suspension, and cancellation-aware behavior.
public final class AsyncClosureDouble<Input, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (Input) async -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed asynchronous behavior used to calculate a result.
    public typealias Handler = (Input) async -> Result

    private let storage: EffectfulClosureDoubleStorage<Input, Result>
    private let forwardingTarget: (@Sendable (Input) async -> Result)?

    /// Creates an empty closure double. Calls require a matching behavior.
    public init() {
        storage = EffectfulClosureDoubleStorage(
            effects: .async
        )
        forwardingTarget = nil
    }

    /// Creates an asynchronous closure spy that delegates unmatched inputs.
    public init(
        forwardingTo target: @escaping @Sendable (Input) async -> Result
    ) {
        storage = EffectfulClosureDoubleStorage(
            effects: .async,
            allowsForwardingFallback: true
        )
        forwardingTarget = target
    }

    /// The ordinary closure value, ready to inject into the subject under test.
    public var function: Function {
        { input in await self(input) }
    }

    /// Invokes and records the double.
    public func callAsFunction(_ input: Input) async -> Result {
        guard let forwardingTarget else {
            return await storage.callAsync(input)
        }
        return await storage.callAsync(
            input,
            forwardingTo: {
                await forwardingTarget(input)
            }
        )
    }

    /// Assigns a name used in strict-scope and interaction diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        storage.stub.named(name)
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
    ) -> AsyncClosureCallPattern<Input, Result> {
        AsyncClosureCallPattern(
            base: pattern(
                matching: PredicateMatcher(description: description, predicate: matcher),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncClosureCallPattern<Input, Result> {
        AsyncClosureCallPattern(
            base: pattern(
                matching: AnyMatcher(),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// A whole-double view of every recorded invocation.
    public var history: InteractionHistory {
        storage.stub.history
    }

    /// Every recorded input, in call order.
    public var invocations: [Input] {
        pattern(matching: AnyMatcher()).arguments()
    }

    /// Reports every behavior registration that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.stub.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior and chain position.
    public func clearRecordedInvocations() {
        storage.stub.clearRecordedInvocations()
    }

    /// Clears configured behavior while preserving recorded calls.
    public func clearConfiguredBehaviors() {
        storage.stub.clearConfiguredBehaviors()
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
    }

    private func pattern(
        matching matcher: ParameterMatcher,
        location: StubSourceLocation? = nil
    ) -> CallPattern<Result> {
        storage.pattern(matching: matcher, location: location)
    }
}

/// A configurable, recordable double for an injected asynchronous throwing
/// unary closure.
///
/// ``AsyncThrowingClosureCallPattern`` composes asynchronous handlers, fixed
/// results and errors, delays, suspension, and cancellation-aware behavior.
public final class AsyncThrowingClosureDouble<Input, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (Input) async throws -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed asynchronous throwing behavior used to calculate a result.
    public typealias Handler = (Input) async throws -> Result

    private let storage: EffectfulClosureDoubleStorage<Input, Result>
    private let forwardingTarget: (@Sendable (Input) async throws -> Result)?

    /// Creates an empty closure double. Calls require a matching behavior.
    public init() {
        storage = EffectfulClosureDoubleStorage(
            effects: .asyncThrowing
        )
        forwardingTarget = nil
    }

    /// Creates an asynchronous throwing closure spy that delegates unmatched
    /// inputs.
    public init(
        forwardingTo target:
            @escaping @Sendable (Input) async throws -> Result
    ) {
        storage = EffectfulClosureDoubleStorage(
            effects: .asyncThrowing,
            allowsForwardingFallback: true
        )
        forwardingTarget = target
    }

    /// The ordinary closure value, ready to inject into the subject under test.
    public var function: Function {
        { input in try await self(input) }
    }

    /// Invokes and records the double.
    public func callAsFunction(_ input: Input) async throws -> Result {
        guard let forwardingTarget else {
            return try await storage.callAsyncThrowing(input)
        }
        return try await storage.callAsyncThrowing(
            input,
            forwardingTo: {
                try await forwardingTarget(input)
            }
        )
    }

    /// Assigns a name used in strict-scope and interaction diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        storage.stub.named(name)
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
        AsyncThrowingClosureCallPattern(
            base: pattern(
                matching: PredicateMatcher(description: description, predicate: matcher),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result> {
        AsyncThrowingClosureCallPattern(
            base: pattern(
                matching: AnyMatcher(),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }

    /// A whole-double view of every recorded invocation.
    public var history: InteractionHistory {
        storage.stub.history
    }

    /// Every recorded input, in call order.
    public var invocations: [Input] {
        pattern(matching: AnyMatcher()).arguments()
    }

    /// Reports every behavior registration that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.stub.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior and chain position.
    public func clearRecordedInvocations() {
        storage.stub.clearRecordedInvocations()
    }

    /// Clears configured behavior while preserving recorded calls.
    public func clearConfiguredBehaviors() {
        storage.stub.clearConfiguredBehaviors()
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
    }

    private func pattern(
        matching matcher: ParameterMatcher,
        location: StubSourceLocation? = nil
    ) -> CallPattern<Result> {
        storage.pattern(matching: matcher, location: location)
    }
}

extension ThrowingClosureDouble where Input: Equatable {
    /// Starts a behavior registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result> {
        ThrowingClosureCallPattern(
            base: pattern(
                matching: EqualMatcher(expected: value),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }
}

extension AsyncClosureDouble where Input: Equatable {
    /// Starts a behavior registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncClosureCallPattern<Input, Result> {
        AsyncClosureCallPattern(
            base: pattern(
                matching: EqualMatcher(expected: value),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }
}

extension AsyncThrowingClosureDouble where Input: Equatable {
    /// Starts a behavior registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result> {
        AsyncThrowingClosureCallPattern(
            base: pattern(
                matching: EqualMatcher(expected: value),
                location: StubSourceLocation(
                    fileID: fileID,
                    filePath: filePath,
                    line: line,
                    column: column
                )
            )
        )
    }
}

extension ThrowingClosureDouble: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

extension AsyncClosureDouble: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

extension AsyncThrowingClosureDouble: @unchecked Sendable
where Input: Sendable, Result: Sendable {}

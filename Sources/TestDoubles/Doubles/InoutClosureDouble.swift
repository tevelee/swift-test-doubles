/// The final argument and return value produced by an `inout` closure call.
public struct InoutClosureOutcome<Value, Result> {
    /// The value written back to the caller.
    public let value: Value

    /// The closure's return value.
    public let result: Result

    /// Creates an `inout` closure outcome.
    public init(value: Value, result: Result) {
        self.value = value
        self.result = result
    }
}

extension InoutClosureOutcome: Sendable
where Value: Sendable, Result: Sendable {}

private struct InoutClosureFixedBehavior<Value, Result>: @unchecked Sendable {
    let value: Value?
    let result: Result
}

/// A reusable `inout` closure-call description.
///
/// Matching uses the value at entry. Handlers receive a mutable copy whose
/// final value is written back to the caller.
public struct InoutClosureCallPattern<Value, Result>: Sendable {
    private let base: ClosureCallPattern<Value, InoutClosureOutcome<Value, Result>>

    fileprivate init(
        base:
            ClosureCallPattern<
                Value,
                InoutClosureOutcome<Value, Result>
            >
    ) {
        self.base = base
    }

    /// An observation-only view of matching invocations.
    public var interactions: CallInteractions {
        base.interactions
    }

    /// The number of matching invocations.
    public var callCount: Int {
        base.callCount
    }

    /// Whether at least one invocation matches this pattern.
    public var wasCalled: Bool {
        base.wasCalled
    }

    /// Verifies matching invocations, expecting exactly one by default.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        base.verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Waits up to `timeout` for matching calls.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.verify(
            expectedCounts,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Returns the values observed before mutation, in call order.
    public func arguments() -> [Value] {
        base.arguments()
    }

    /// Returns a stream of future values observed before mutation.
    public func stream() -> InvocationStream<Value> {
        base.stream()
    }

    /// Returns values written back by completed configured handlers.
    public func mutatedValues() -> [Value] {
        base.results().map(\.value)
    }

    /// Returns results produced by completed configured handlers.
    public func results() -> [Result] {
        base.results().map(\.result)
    }

    /// Completion states for matching calls.
    public func outcomes() -> [InvocationOutcome<Result>] {
        base.outcomes().map { outcome in
            switch outcome {
                case .returned(let result):
                    return .returned(result.result)
                case .threw(let error):
                    return .threw(error)
                case .pending:
                    return .pending
                case .forwarded:
                    return .forwarded
                case .unavailable:
                    return .unavailable
            }
        }
    }

    /// Monotonic timing information for matching calls.
    public func timings() -> [InvocationTiming] {
        base.timings()
    }

    /// Runs `handler` for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (inout Value) -> Result
    ) -> InoutClosureBehaviorChain<Value, Result> {
        InoutClosureBehaviorChain(
            base: base.then(times: times) { input in
                var value = input
                let result = handler(&value)
                return InoutClosureOutcome(
                    value: value,
                    result: result
                )
            }
        )
    }

    /// Runs `handler` for every matching invocation from here on.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (inout Value) -> Result
    ) -> CallInteractions {
        base.then(times: times) { input in
            var value = input
            let result = handler(&value)
            return InoutClosureOutcome(
                value: value,
                result: result
            )
        }.interactions
    }

    /// Returns `result` without changing the argument.
    @discardableResult
    public func thenReturn(_ result: Result) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior<Value, Result>(
            value: nil,
            result: result
        )
        return then(times: 1...) { _ in behavior.result }
    }

    /// Writes `value` and returns `result` for every matching invocation.
    @discardableResult
    public func thenMutate(
        to value: Value,
        returning result: Result
    ) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior(
            value: value,
            result: result
        )
        return then(times: 1...) { input in
            input = behavior.value!
            return behavior.result
        }
    }

    /// Forwards every matching call through an `inout` closure spy.
    @discardableResult
    public func thenForward() -> CallInteractions {
        base.thenForward().interactions
    }
}

extension InoutClosureCallPattern where Result == Void {
    /// Leaves the argument unchanged and completes normally.
    @discardableResult
    public func thenDoNothing() -> CallInteractions {
        then(times: 1...) { _ in }
    }

    /// Writes `value` for every matching invocation.
    @discardableResult
    public func thenMutate(to value: Value) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior(
            value: value,
            result: ()
        )
        return then(times: 1...) { input in input = behavior.value! }
    }
}

/// A chain of consecutive `inout` closure behaviors.
public struct InoutClosureBehaviorChain<Value, Result> {
    private let base: StubBehaviorChain<InoutClosureOutcome<Value, Result>>

    fileprivate init(
        base:
            StubBehaviorChain<
                InoutClosureOutcome<Value, Result>
            >
    ) {
        self.base = base
    }

    /// An observation-only view of invocations matching this chain.
    public var interactions: CallInteractions {
        base.interactions
    }

    /// Appends `handler` for `times` consecutive matching invocations.
    @discardableResult
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (inout Value) -> Result
    ) -> Self {
        Self(
            base: base.then(times: times) { (input: Value) in
                var value = input
                let result = handler(&value)
                return InoutClosureOutcome(
                    value: value,
                    result: result
                )
            }
        )
    }

    /// Appends `handler` for every matching invocation from here on.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (inout Value) -> Result
    ) -> CallInteractions {
        base.then(times: times) { (input: Value) in
            var value = input
            let result = handler(&value)
            return InoutClosureOutcome(
                value: value,
                result: result
            )
        }.interactions
    }

    /// Appends `result` without changing the argument.
    @discardableResult
    public func thenReturn(_ result: Result) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior<Value, Result>(
            value: nil,
            result: result
        )
        return then(times: 1...) { _ in behavior.result }
    }

    /// Appends a fixed mutation and result.
    @discardableResult
    public func thenMutate(
        to value: Value,
        returning result: Result
    ) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior(
            value: value,
            result: result
        )
        return then(times: 1...) { input in
            input = behavior.value!
            return behavior.result
        }
    }

    /// Appends forwarding for `times` matching calls.
    @discardableResult
    public func thenForward(times: Int = 1) -> Self {
        Self(base: base.thenForward(times: times))
    }

    /// Forwards every matching call from here on.
    @discardableResult
    public func thenForward(
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenForward(times: times).interactions
    }
}

extension InoutClosureBehaviorChain where Result == Void {
    /// Appends a no-op behavior.
    @discardableResult
    public func thenDoNothing() -> CallInteractions {
        then(times: 1...) { _ in }
    }

    /// Appends a fixed mutation.
    @discardableResult
    public func thenMutate(to value: Value) -> CallInteractions {
        let behavior = InoutClosureFixedBehavior(
            value: value,
            result: ()
        )
        return then(times: 1...) { input in input = behavior.value! }
    }
}

/// A configurable double for a synchronous `(inout Value) -> Result` closure.
///
/// Invocation history stores the value at entry. ``InoutClosureCallPattern``
/// additionally exposes the values written back by configured handlers.
public final class InoutClosureDouble<Value, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (inout Value) -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Value) -> Bool

    /// Typed behavior used to mutate the argument and calculate a result.
    public typealias Handler = @Sendable (inout Value) -> Result

    private let base: ClosureDouble<Value, InoutClosureOutcome<Value, Result>>

    /// Creates an empty `inout` closure double.
    public init() {
        base = ClosureDouble()
    }

    /// Creates an `inout` closure spy that delegates unmatched calls.
    public init(
        forwardingTo target: @escaping @Sendable (inout Value) -> Result
    ) {
        base = ClosureDouble(
            forwardingTo: { input in
                var value = input
                let result = target(&value)
                return InoutClosureOutcome(
                    value: value,
                    result: result
                )
            }
        )
    }

    /// The `inout` closure value ready to inject.
    public var function: Function {
        { value in self(&value) }
    }

    /// Invokes the double and writes the configured mutation back to `value`.
    public func callAsFunction(_ value: inout Value) -> Result {
        let outcome = base(value)
        value = outcome.value
        return outcome.result
    }

    /// Assigns a diagnostic name.
    @discardableResult
    public func named(_ name: String) -> Self {
        base.named(name)
        return self
    }

    /// Starts a behavior registration selected by the value at entry.
    public func when(
        _ matcher: @escaping Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> InoutClosureCallPattern<Value, Result> {
        InoutClosureCallPattern(
            base: base.when(
                matcher,
                describedBy: description,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        )
    }

    /// Starts a behavior registration that accepts every invocation.
    public func whenAny(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> InoutClosureCallPattern<Value, Result> {
        InoutClosureCallPattern(
            base: base.whenAny(
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        )
    }

    /// A whole-double view of every recorded invocation.
    public var history: InteractionHistory {
        base.history
    }

    /// Number of recorded invocations.
    public var callCount: Int {
        base.callCount
    }

    /// Every value observed before mutation, in call order.
    public var invocations: [Value] {
        base.invocations
    }

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

extension InoutClosureDouble where Value: Equatable {
    /// Starts a registration for an entry value equal to `value`.
    public func when(
        equal value: Value,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> InoutClosureCallPattern<Value, Result> {
        InoutClosureCallPattern(
            base: base.when(
                equal: value,
                fileID: fileID,
                filePath: filePath,
                line: line,
                column: column
            )
        )
    }
}

extension InoutClosureDouble: @unchecked Sendable
where Value: Sendable, Result: Sendable {}

extension InoutClosureDouble
where Value: Sendable, Result: Sendable {
    /// A checked `@Sendable` `inout` closure value.
    public var sendableFunction: @Sendable (inout Value) -> Result {
        { value in self(&value) }
    }
}

/// An `inout` closure double configured with a live fallback.
public typealias InoutClosureSpy<Value, Result> =
    InoutClosureDouble<Value, Result>

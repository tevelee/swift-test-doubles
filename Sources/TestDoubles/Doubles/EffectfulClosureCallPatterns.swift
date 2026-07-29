/// A reusable synchronous throwing closure-call description.
///
/// The pattern preserves `Input` for handler, argument-history, and stream
/// inference while delegating behavior and observation to ``CallPattern``.
public struct ThrowingClosureCallPattern<Input, Result>: Sendable {
    let base: CallPattern<Result>

    init(base: CallPattern<Result>) {
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

    /// Waits up to `timeout` for the lower-bound count of matching calls.
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

    /// Waits for matching calls using `clock` rather than wall time.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.verify(
            expectedCounts,
            within: timeout,
            using: clock,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Returns matching inputs in call order.
    public func arguments() -> [Input] {
        base.arguments()
    }

    /// Returns a stream of future matching inputs.
    public func stream() -> InvocationStream<Input> {
        base.stream()
    }

    /// Returns `value` for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenReturn(value, times: times)
    }

    /// Returns `value` for every matching invocation from here on.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenReturn(value, times: times)
    }

    /// Returns the listed values in order, then repeats the final value.
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> CallInteractions {
        appendRepeatingValues(base: base, first: first, second: second, rest: rest)
    }

    /// Configures a finite, inspectable queue of fixed return values.
    public func thenQueue(
        _ first: Result,
        _ rest: Result...
    ) -> StubBehaviorQueue {
        makeClosureBehaviorQueue(base: base, first: first, rest: rest)
    }

    /// Halts with an actionable diagnostic for every matching invocation.
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> CallInteractions {
        base.thenFatalError(message)
    }
}

/// A reusable asynchronous non-throwing closure-call description.
///
/// The pattern exposes only outcomes valid for `(Input) async -> Result`,
/// including delayed returns, suspension, and cancellation-aware completion.
public struct AsyncClosureCallPattern<Input, Result>: Sendable {
    let base: CallPattern<Result>

    init(base: CallPattern<Result>) {
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

    /// Waits up to `timeout` for the lower-bound count of matching calls.
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

    /// Waits for matching calls using `clock` rather than wall time.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.verify(
            expectedCounts,
            within: timeout,
            using: clock,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Returns matching inputs in call order.
    public func arguments() -> [Input] {
        base.arguments()
    }

    /// Returns a stream of future matching inputs.
    public func stream() -> InvocationStream<Input> {
        base.stream()
    }

    /// Returns `value` for `times` consecutive matching invocations.
    ///
    /// `after:` delays delivery without blocking the caller's executor.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenReturn(value, after: delay, times: times)
    }

    /// Returns `value` for every matching invocation from here on.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenReturn(value, after: delay, times: times)
    }

    /// Returns the listed values in order, then repeats the final value.
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> CallInteractions {
        appendRepeatingValues(base: base, first: first, second: second, rest: rest)
    }

    /// Returns `value` after a delay measured by `clock`.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration,
        using clock: any StubClock
    ) -> CallInteractions {
        base.thenReturn(value, after: delay, using: clock)
    }

    /// Configures a finite, inspectable queue of fixed return values.
    public func thenQueue(
        _ first: Result,
        _ rest: Result...
    ) -> StubBehaviorQueue {
        makeClosureBehaviorQueue(base: base, first: first, rest: rest)
    }

    /// Halts with an actionable diagnostic for every matching invocation.
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> CallInteractions {
        base.thenFatalError(message)
    }

    /// Parks every matching invocation without ever completing it.
    @discardableResult
    public func thenNeverReturn() -> CallInteractions {
        base.thenNeverReturn()
    }

    /// Parks matching invocations until the test resumes them explicitly.
    public func thenSuspend() -> StubSuspension<Result> {
        base.thenSuspend()
    }

    /// Waits for cancellation, then returns `value`.
    @discardableResult
    public func thenAwaitCancellation(
        returning value: Result
    ) -> CallInteractions {
        base.thenAwaitCancellation(returning: value)
    }
}

/// A reusable asynchronous throwing closure-call description.
///
/// The pattern exposes outcomes valid for `(Input) async throws -> Result`,
/// including fixed errors, delayed completion, suspension, and cancellation.
public struct AsyncThrowingClosureCallPattern<Input, Result>: Sendable {
    let base: CallPattern<Result>

    init(base: CallPattern<Result>) {
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

    /// Waits up to `timeout` for the lower-bound count of matching calls.
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

    /// Waits for matching calls using `clock` rather than wall time.
    public func verify(
        _ expectedCounts: PartialRangeFrom<Int> = 1...,
        within timeout: Duration,
        using clock: any StubClock,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.verify(
            expectedCounts,
            within: timeout,
            using: clock,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Returns matching inputs in call order.
    public func arguments() -> [Input] {
        base.arguments()
    }

    /// Returns a stream of future matching inputs.
    public func stream() -> InvocationStream<Input> {
        base.stream()
    }

    /// Returns `value` for `times` consecutive matching invocations.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenReturn(value, after: delay, times: times)
    }

    /// Returns `value` for every matching invocation from here on.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        times: PartialRangeFrom<Int> = 1...
    ) -> CallInteractions {
        base.thenReturn(value, after: delay, times: times)
    }

    /// Returns the listed values in order, then repeats the final value.
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> CallInteractions {
        appendRepeatingValues(base: base, first: first, second: second, rest: rest)
    }

    /// Returns `value` after a delay measured by `clock`.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration,
        using clock: any StubClock
    ) -> CallInteractions {
        base.thenReturn(value, after: delay, using: clock)
    }

    /// Configures a finite, inspectable queue of fixed return values.
    public func thenQueue(
        _ first: Result,
        _ rest: Result...
    ) -> StubBehaviorQueue {
        makeClosureBehaviorQueue(base: base, first: first, rest: rest)
    }

    /// Halts with an actionable diagnostic for every matching invocation.
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> CallInteractions {
        base.thenFatalError(message)
    }

    /// Parks every matching invocation without ever completing it.
    @discardableResult
    public func thenNeverReturn() -> CallInteractions {
        base.thenNeverReturn()
    }

    /// Parks matching invocations until the test resumes them explicitly.
    public func thenSuspend() -> StubSuspension<Result> {
        base.thenSuspend()
    }

    /// Waits for cancellation and uses the requirement's throwing outcome.
    @discardableResult
    public func thenAwaitCancellation() -> CallInteractions {
        base.thenAwaitCancellation()
    }

    /// Waits for cancellation, then returns `value`.
    @discardableResult
    public func thenAwaitCancellation(
        returning value: Result
    ) -> CallInteractions {
        base.thenAwaitCancellation(returning: value)
    }

    /// Waits for cancellation, then throws `error`.
    @discardableResult
    public func thenAwaitCancellation<Failure: Error>(
        throwing error: Failure
    ) -> CallInteractions {
        base.thenAwaitCancellation(throwing: error)
    }
}

private func appendRepeatingValues<Result>(
    base: CallPattern<Result>,
    first: Result,
    second: Result,
    rest: [Result]
) -> CallInteractions {
    let values = [first, second] + rest
    for value in values {
        base.recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: base.recording.methodIndex
        )
    }
    _ = base.makeBehaviorChain(
        values.dropLast().map { (.value(.success($0)), .exactly(1)) }
            + [(.value(.success(rest.last ?? second)), .unbounded)]
    )
    return base.interactions
}

private func makeClosureBehaviorQueue<Result>(
    base: CallPattern<Result>,
    first: Result,
    rest: [Result]
) -> StubBehaviorQueue {
    let values = [first] + rest
    for value in values {
        base.recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: base.recording.methodIndex
        )
    }
    return base.makeBehaviorChain(
        values.map { (.value(.success($0)), .exactly(1)) }
    ).behaviorQueue
}

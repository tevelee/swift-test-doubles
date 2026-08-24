private struct ClosureDoubleConformer<Input, Result>: ManualStubConformer {
    let stub: ManualStub<Self>
}

/// A reusable unary-closure call description for behavior and interaction
/// operations.
///
/// This façade preserves `Input` for handler and stream inference while
/// delegating storage, fixed behavior chains, verification, and ordering to
/// the same engine as ``CallPattern``.
public struct ClosureCallPattern<Input, Result>: Sendable {
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
    /// A later behavior takes over after the explicit count. Omitting
    /// `times:` makes an intermediate behavior one-shot.
    @discardableResult
    @_disfavoredOverload
    public func thenReturn(
        _ value: Result,
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenReturn(value, times: times)
    }

    /// Returns `value` to every matching invocation from here on.
    ///
    /// Omitting `times:` resolves here when this is the trailing behavior.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenReturn(value, times: times)
    }

    /// Returns the listed values in order, then repeats the final value.
    @discardableResult
    public func thenReturn(
        _ first: Result,
        _ second: Result,
        _ rest: Result...
    ) -> ConfiguredCall<Result> {
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
        return base.configuredCall
    }

    /// Computes `times` matching results from the closure's typed input.
    ///
    /// Omitting `times:` resolves here when another behavior follows, making
    /// this intermediate behavior exactly once.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable (Input) -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Computes every matching result from the closure's typed input from here
    /// on.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Input) -> Result
    ) -> ConfiguredCall<Result> {
        base.then(times: times, handler)
    }

    /// Computes `times` matching results without reading the closure's input.
    @discardableResult
    @_disfavoredOverload
    public func then(
        times: Int = 1,
        _ handler: @escaping @Sendable () -> Result
    ) -> StubBehaviorChain<Result> {
        base.then(times: times, handler)
    }

    /// Computes every matching result from here on without reading the
    /// closure's input.
    @discardableResult
    public func then(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable () -> Result
    ) -> ConfiguredCall<Result> {
        base.then(times: times, handler)
    }

    /// Computes `times` matching results from a one-based call count and the
    /// closure's typed input. The count starts at 1 for this behavior.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int, Input) -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from here on using a one-based call
    /// count and the closure's typed input.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int, Input) -> Result
    ) -> ConfiguredCall<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes `times` matching results from only a one-based call count. The
    /// count starts at 1 for this behavior.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCall(
        times: Int = 1,
        _ handler: @escaping @Sendable (Int) -> Result
    ) -> StubBehaviorChain<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Computes every matching result from here on using only a one-based call
    /// count.
    @discardableResult
    public func thenForEachCall(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (Int) -> Result
    ) -> ConfiguredCall<Result> {
        base.thenForEachCall(times: times, handler)
    }

    /// Configures a finite, inspectable queue of fixed return values.
    public func thenQueue(
        _ first: Result,
        _ rest: Result...
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

    /// Halts with an actionable diagnostic for every matching invocation.
    @discardableResult
    public func thenFatalError(_ message: String? = nil) -> ConfiguredCall<Result> {
        base.thenFatalError(message)
    }
}

extension ClosureCallPattern where Result == Void {
    /// Completes `times` consecutive matching invocations without additional
    /// work.
    @discardableResult
    @_disfavoredOverload
    public func thenDoNothing(times: Int = 1) -> StubBehaviorChain<Void> {
        base.thenDoNothing(times: times)
    }

    /// Completes every matching invocation without additional work.
    ///
    /// Omitting `times:` resolves here when this is the trailing behavior.
    @discardableResult
    public func thenDoNothing(
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenDoNothing(times: times)
    }
}

/// A configurable, recordable double for an injected synchronous unary
/// closure.
///
/// `ClosureDouble<Input, Result>` represents `(Input) -> Result`; its
/// ``function`` property can be passed directly where that closure type is
/// required. `when` returns a typed ``ClosureCallPattern`` backed by the same
/// behavior and observation engine as protocol stubs, so fixed chains, custom
/// handlers, call-count ranges, typed arguments, streams, and
/// ``InvocationOrder`` compose the same way.
///
/// ```swift
/// let formatter = ClosureDouble<Int, String>()
/// let evens = formatter.when { $0.isMultiple(of: 2) }
///     .thenReturn("first even")
///     .thenReturn("even")
/// formatter.whenAny().then { "odd-\($0)" }
///
/// let format: (Int) -> String = formatter.function
/// _ = format(2)
/// evens.verify()
/// ```
public final class ClosureDouble<Input, Result> {
    /// The closure shape represented by this double.
    public typealias Function = (Input) -> Result

    /// Predicate used to select a configured behavior.
    public typealias Matcher = @Sendable (Input) -> Bool

    /// Typed behavior used to calculate a result.
    public typealias Handler = @Sendable (Input) -> Result

    private let storage: ManualStub<ClosureDoubleConformer<Input, Result>>
    private let forwardingTarget: (@Sendable (Input) -> Result)?

    private var route: ManualMethodRouteIdentity {
        .typed(
            ManualRouteID(
                "callAsFunction(_:)",
                argumentTypeIDs: [ObjectIdentifier(Input.self)]
            )
        )
    }

    /// Creates an empty closure double. Calls require a matching behavior.
    public init() {
        storage = ManualStub()
        forwardingTarget = nil
    }

    /// Creates a closure spy that records calls and delegates unmatched inputs.
    ///
    /// Configured behaviors take precedence. Use `thenForward()` on a matching
    /// registration to explicitly delegate that call to `target`.
    public init(
        forwardingTo target: @escaping @Sendable (Input) -> Result
    ) {
        storage = ManualStub(
            materializing: { ClosureDoubleConformer(stub: $0) },
            allowsForwardingFallback: true
        )
        forwardingTarget = target
    }

    /// The ordinary closure value, ready to inject into the subject under test.
    public var function: Function {
        { input in self(input) }
    }

    /// Invokes the double. A call is recorded before its configured behavior
    /// runs, matching ``Stub`` and ``ManualStub`` observation semantics.
    public func callAsFunction(_ input: Input) -> Result {
        guard let forwardingTarget else {
            return storage.dispatchMethod(route: route, args: [input])
        }
        let method = storage.internMethod(
            route: route,
            returnType: Result.self,
            isAsync: false,
            isThrowing: false
        )
        return storage.dispatchValue(
            method: method,
            args: [input],
            forwardingTo: {
                forwardingTarget(input)
            }
        )
    }

    /// Assigns a name used in strict-scope and interaction diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        storage.named(name)
        return self
    }

    /// Starts a behavior registration selected by `matcher`.
    ///
    /// The returned ``ClosureCallPattern`` can be retained for later
    /// verification or completed inline with any behavior supported by a
    /// synchronous nonthrowing call.
    public func when(
        _ matcher: @escaping Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ClosureCallPattern<Input, Result> {
        ClosureCallPattern(
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
    ) -> ClosureCallPattern<Input, Result> {
        ClosureCallPattern(
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

    /// An observation-only view of every closure invocation.
    public var interactions: CallInteractions {
        pattern(matching: AnyMatcher()).interactions
    }

    /// A whole-double view of every recorded closure invocation.
    public var history: InteractionHistory {
        storage.history
    }

    /// Number of recorded invocations.
    public var callCount: Int {
        interactions.callCount
    }

    /// Whether at least one invocation was recorded.
    public var wasCalled: Bool {
        interactions.wasCalled
    }

    /// Every recorded input, in call order.
    public var invocations: [Input] {
        interactions.arguments()
    }

    /// Number of recorded invocations matching `matcher`.
    public func callCount(
        matching matcher: @escaping Matcher,
        describedBy description: String = "predicate"
    ) -> Int {
        pattern(
            matching: PredicateMatcher(description: description, predicate: matcher)
        ).callCount
    }

    /// Verifies how many recorded invocations satisfy `matcher`, expecting
    /// exactly one by default.
    ///
    /// Prefer retaining the ``ClosureCallPattern`` returned by `when` when the
    /// same matcher also configured behavior; this direct form remains useful
    /// for verification-only predicates.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
        matching matcher: @escaping Matcher,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        pattern(
            matching: PredicateMatcher(description: description, predicate: matcher)
        ).verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that no calls were recorded.
    public func verifyNoInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        interactions.verify(
            .never,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Reports every call not covered by a successful verification.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Reports every behavior registration that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior and chain position.
    public func clearRecordedInvocations() {
        storage.clearRecordedInvocations()
    }

    /// Clears configured behavior while preserving recorded calls.
    public func clearConfiguredBehaviors() {
        storage.clearConfiguredBehaviors()
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        clearConfiguredBehaviors()
        clearRecordedInvocations()
    }

    /// Returns a human-readable ordered log of every closure invocation.
    public func describeInteractions() -> String {
        storage.describeInteractions()
    }

    /// Returns a chronological diagnostic view of every closure invocation.
    public func interactionTimeline() -> InteractionTimeline {
        storage.interactionTimeline()
    }

    private func pattern(
        matching matcher: ParameterMatcher,
        location: StubSourceLocation? = nil
    ) -> CallPattern<Result> {
        let method = storage.recorder.internManualMethod(
            route: route,
            kind: .method,
            returnType: Result.self,
            isAsync: false,
            isThrowing: false
        )
        let recording = RecordedCall(
            methodIndex: method.index,
            name: method.name,
            args: [],
            matchers: [matcher]
        ).taggingRegistrationLocation(location)
        return CallPattern<Result>(recorder: storage.recorder, recording: recording)
    }
}

/// A closure double is safe to share when its input and result values are safe
/// to transfer. Its recorder serializes registration and invocation state.
extension ClosureDouble: @unchecked Sendable where Input: Sendable, Result: Sendable {}

/// A configurable, recordable double for a nullary synchronous closure.
///
/// `when()` returns a ``ClosureCallPattern`` backed by the same behavior and
/// observation engine as unary closure and protocol doubles.
public final class VoidClosureDouble<Result> {
    private let storage = ClosureDouble<Void, Result>()

    /// Creates an empty nullary closure double.
    public init() {}

    /// The ordinary nullary closure ready to inject into a subject.
    public var function: () -> Result {
        { self() }
    }

    /// Invokes the double.
    public func callAsFunction() -> Result {
        storage(())
    }

    /// Assigns a name used in strict-scope and interaction diagnostics.
    @discardableResult
    public func named(_ name: String) -> Self {
        storage.named(name)
        return self
    }

    /// Starts an always-matching behavior registration.
    public func when(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ClosureCallPattern<Void, Result> {
        storage.whenAny(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// An observation-only view of every invocation.
    public var interactions: CallInteractions {
        storage.interactions
    }

    /// A whole-double view of every recorded invocation.
    public var history: InteractionHistory {
        storage.history
    }

    /// Number of recorded invocations.
    public var callCount: Int {
        interactions.callCount
    }

    /// Whether at least one invocation was recorded.
    public var wasCalled: Bool {
        interactions.wasCalled
    }

    /// Verifies the number of invocations, expecting exactly one by default.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        interactions.verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Verifies that no calls were recorded.
    public func verifyNoInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Reports every call not covered by a successful verification.
    public func verifyNoMoreInteractions(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoMoreInteractions(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Reports every behavior registration that no invocation matched.
    public func verifyNoUnusedStubs(
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        storage.verifyNoUnusedStubs(
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }

    /// Clears calls while preserving configured behavior and chain position.
    public func clearRecordedInvocations() {
        storage.clearRecordedInvocations()
    }

    /// Clears configured behavior while preserving recorded calls.
    public func clearConfiguredBehaviors() {
        storage.clearConfiguredBehaviors()
    }

    /// Clears configured behavior and recorded invocations.
    public func reset() {
        storage.reset()
    }

    /// Returns a human-readable ordered log of every invocation.
    public func describeInteractions() -> String {
        storage.describeInteractions()
    }

    /// Returns a chronological diagnostic view of every invocation.
    public func interactionTimeline() -> InteractionTimeline {
        storage.interactionTimeline()
    }
}

/// A nullary closure double is safe to share when its result values are safe
/// to transfer. Its recorder serializes registration and invocation state.
extension VoidClosureDouble: @unchecked Sendable where Result: Sendable {}

extension ClosureDouble where Input: Equatable {
    /// Starts a behavior registration for an input equal to `value`.
    public func when(
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ClosureCallPattern<Input, Result> {
        ClosureCallPattern(
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

    /// Verifies calls that received an input equal to `value`.
    ///
    /// Prefer retaining the ``ClosureCallPattern`` returned by `when(equal:)`
    /// when it also configured behavior.
    public func verify(
        _ expectedCounts: any RangeExpression<Int> = 1 ... 1,
        equal value: Input,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        pattern(matching: EqualMatcher(expected: value)).verify(
            expectedCounts,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

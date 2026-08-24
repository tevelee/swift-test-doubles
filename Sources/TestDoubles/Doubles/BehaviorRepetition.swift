/// Explicit repetition choices for configured behaviors.
///
/// Use ``Finite`` when another behavior may follow and ``Forever`` for a
/// terminal fallback. Distinct types keep the resulting chain shape visible
/// to the compiler:
///
/// ```swift
/// stub.when { $0.load() }
///     .thenReturn("cached", repeating: .times(2))
///     .thenReturn("live", repeating: .forever)
/// ```
public enum BehaviorRepetition {
    /// A bounded repetition that leaves the behavior chain open.
    public struct Finite: Sendable, Hashable {
        /// Runs the behavior once.
        public static let once = Self(count: 1)

        /// Runs the behavior exactly `count` times.
        ///
        /// - Precondition: `count` is at least one.
        public static func times(_ count: Int) -> Self {
            Self(count: validatedRepeatCount(count))
        }

        let count: Int

        private init(count: Int) {
            self.count = count
        }
    }

    /// An unbounded repetition that terminates the behavior chain.
    public struct Forever: Sendable, Hashable {
        /// Runs the behavior for every remaining matching invocation.
        public static let forever = Self()

        private init() {}
    }
}

extension CallPattern {
    /// Returns `value` for a finite number of matching invocations.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> StubBehaviorChain<Result> {
        thenReturn(value, after: delay, times: repetition.count)
    }

    /// Returns `value` for every remaining matching invocation.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenReturn(value, after: delay, times: 1...)
    }

    /// Throws `error` for a finite number of matching invocations.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> StubBehaviorChain<Result> {
        thenThrow(error, after: delay, times: repetition.count)
    }

    /// Throws `error` for every remaining matching invocation.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenThrow(error, after: delay, times: 1...)
    }

    /// Forwards a finite number of matching invocations to the spy target.
    @discardableResult
    public func thenForward(
        repeating repetition: BehaviorRepetition.Finite
    ) -> StubBehaviorChain<Result> {
        thenForward(times: repetition.count)
    }

    /// Forwards every remaining matching invocation to the spy target.
    @discardableResult
    public func thenForward(
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenForward(times: 1...)
    }
}

extension CallPattern where Result == Void {
    /// Completes a finite number of matching invocations without a value.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> StubBehaviorChain<Void> {
        thenDoNothing(after: delay, times: repetition.count)
    }

    /// Completes every remaining matching invocation without a value.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Void> {
        thenDoNothing(after: delay, times: 1...)
    }
}

extension StubBehaviorChain {
    /// Appends a finite fixed return behavior.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> Self {
        thenReturn(value, after: delay, times: repetition.count)
    }

    /// Appends a terminal fixed return behavior.
    @discardableResult
    public func thenReturn(
        _ value: Result,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenReturn(value, after: delay, times: 1...)
    }

    /// Appends a finite fixed error behavior.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> Self {
        thenThrow(error, after: delay, times: repetition.count)
    }

    /// Appends a terminal fixed error behavior.
    @discardableResult
    public func thenThrow<Failure: Error>(
        _ error: Failure,
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenThrow(error, after: delay, times: 1...)
    }

    /// Appends a finite forwarding behavior.
    @discardableResult
    public func thenForward(
        repeating repetition: BehaviorRepetition.Finite
    ) -> Self {
        thenForward(times: repetition.count)
    }

    /// Appends a terminal forwarding behavior.
    @discardableResult
    public func thenForward(
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Result> {
        thenForward(times: 1...)
    }
}

extension StubBehaviorChain where Result == Void {
    /// Appends a finite no-op behavior.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Finite
    ) -> Self {
        thenDoNothing(after: delay, times: repetition.count)
    }

    /// Appends a terminal no-op behavior.
    @discardableResult
    public func thenDoNothing(
        after delay: Duration? = nil,
        repeating repetition: BehaviorRepetition.Forever
    ) -> ConfiguredCall<Void> {
        thenDoNothing(after: delay, times: 1...)
    }
}

/// A synchronous closure double that forwards unmatched calls to a live
/// closure.
///
/// Construct it with ``ClosureDouble/init(forwardingTo:)``. Configured
/// behaviors override the live closure, while `thenForward()` restores
/// delegation for selected calls.
public typealias ClosureSpy<Input, Result> = ClosureDouble<Input, Result>

/// A synchronous throwing closure double that forwards unmatched calls.
public typealias ThrowingClosureSpy<Input, Result> =
    ThrowingClosureDouble<Input, Result>

/// An asynchronous closure double that forwards unmatched calls.
public typealias AsyncClosureSpy<Input, Result> =
    AsyncClosureDouble<Input, Result>

/// An asynchronous throwing closure double that forwards unmatched calls.
public typealias AsyncThrowingClosureSpy<Input, Result> =
    AsyncThrowingClosureDouble<Input, Result>

extension ClosureCallPattern {
    /// Forwards `times` matching calls through a closure spy.
    @discardableResult
    @_disfavoredOverload
    public func thenForward(
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenForward(times: times)
    }

    /// Forwards every matching call from here on through a closure spy.
    @discardableResult
    public func thenForward(
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenForward(times: times)
    }
}

extension ThrowingClosureCallPattern {
    /// Forwards `times` matching calls through a throwing closure spy.
    @discardableResult
    @_disfavoredOverload
    public func thenForward(
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenForward(times: times)
    }

    /// Forwards every matching call from here on through a closure spy.
    @discardableResult
    public func thenForward(
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenForward(times: times)
    }
}

extension AsyncClosureCallPattern {
    /// Forwards `times` matching calls through an asynchronous closure spy.
    @discardableResult
    @_disfavoredOverload
    public func thenForward(
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenForward(times: times)
    }

    /// Forwards every matching call from here on through a closure spy.
    @discardableResult
    public func thenForward(
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenForward(times: times)
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Forwards `times` matching calls through an asynchronous throwing
    /// closure spy.
    @discardableResult
    @_disfavoredOverload
    public func thenForward(
        times: Int = 1
    ) -> StubBehaviorChain<Result> {
        base.thenForward(times: times)
    }

    /// Forwards every matching call from here on through a closure spy.
    @discardableResult
    public func thenForward(
        times: PartialRangeFrom<Int> = 1...
    ) -> ConfiguredCall<Result> {
        base.thenForward(times: times)
    }
}

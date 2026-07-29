extension CallPattern {
    /// Throws `error` on every `interval`th matching call and returns `value`
    /// for the other calls.
    ///
    /// Counting is scoped to this registration and starts at one. The
    /// decision is reserved in invocation order, including under concurrent
    /// callers.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        every interval: Int,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        precondition(
            interval > 0,
            "[TestDoubles] thenInjectFailure(every:) requires a positive interval."
        )
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        return installFaultInjection(
            rule: .every(interval),
            seed: 0,
            error: error,
            value: value
        )
    }

    /// Throws `error` with a deterministic seeded probability and returns
    /// `value` for the other matching calls.
    ///
    /// Reusing the same seed and probability produces the same outcome
    /// sequence. `probability` must be between zero and one.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        probability: Double,
        seed: UInt64,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        precondition(
            probability.isFinite && (0 ... 1).contains(probability),
            "[TestDoubles] thenInjectFailure(probability:) requires a finite value from 0 through 1."
        )
        let method = requireRuntimeMethod()
        requireValidThrownError(error, for: method)
        recorder.requireReturnValueMatchesRuntimeType(
            value,
            for: recording.methodIndex
        )
        return installFaultInjection(
            rule: .probability(probability),
            seed: seed,
            error: error,
            value: value
        )
    }

    private func installFaultInjection<Failure: Error>(
        rule: StubBehaviorRegistry.FaultInjectionSchedule.Rule,
        seed: UInt64,
        error: Failure,
        value: Result
    ) -> CallInteractions {
        let schedule = StubBehaviorRegistry.FaultInjectionSchedule(
            rule: rule,
            seed: seed,
            failure: .failure(error),
            success: .success(value)
        )
        _ = makeBehaviorChain([
            (.faultInjection(schedule), .unbounded)
        ])
        return interactions
    }
}

extension ThrowingClosureCallPattern {
    /// Injects a failure on every `interval`th matching closure invocation.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        every interval: Int,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        base.thenInjectFailure(
            every: interval,
            throwing: error,
            otherwiseReturning: value
        )
    }

    /// Injects failures using a reproducible seeded probability.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        probability: Double,
        seed: UInt64,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        base.thenInjectFailure(
            probability: probability,
            seed: seed,
            throwing: error,
            otherwiseReturning: value
        )
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Injects a failure on every `interval`th matching closure invocation.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        every interval: Int,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        base.thenInjectFailure(
            every: interval,
            throwing: error,
            otherwiseReturning: value
        )
    }

    /// Injects failures using a reproducible seeded probability.
    @discardableResult
    public func thenInjectFailure<Failure: Error>(
        probability: Double,
        seed: UInt64,
        throwing error: Failure,
        otherwiseReturning value: Result
    ) -> CallInteractions {
        base.thenInjectFailure(
            probability: probability,
            seed: seed,
            throwing: error,
            otherwiseReturning: value
        )
    }
}

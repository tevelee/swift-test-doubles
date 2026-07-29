extension ClosureCallPattern {
    /// Returned values from completed matching calls.
    public func results() -> [Result] { base.results() }

    /// Errors thrown by completed matching calls.
    public func errors() -> [any Error] { base.errors() }

    /// Completion states for matching calls.
    public func outcomes() -> [InvocationOutcome<Result>] { base.outcomes() }

    /// The most recently entered matching call's completion state.
    public var lastOutcome: InvocationOutcome<Result>? { base.lastOutcome }
}

extension ThrowingClosureCallPattern {
    /// Returned values from completed matching calls.
    public func results() -> [Result] { base.results() }

    /// Errors thrown by completed matching calls.
    public func errors() -> [any Error] { base.errors() }

    /// Completion states for matching calls.
    public func outcomes() -> [InvocationOutcome<Result>] { base.outcomes() }

    /// The most recently entered matching call's completion state.
    public var lastOutcome: InvocationOutcome<Result>? { base.lastOutcome }
}

extension AsyncClosureCallPattern {
    /// Returned values from completed matching calls.
    public func results() -> [Result] { base.results() }

    /// Errors thrown by completed matching calls.
    public func errors() -> [any Error] { base.errors() }

    /// Completion states for matching calls.
    public func outcomes() -> [InvocationOutcome<Result>] { base.outcomes() }

    /// The most recently entered matching call's completion state.
    public var lastOutcome: InvocationOutcome<Result>? { base.lastOutcome }
}

extension AsyncThrowingClosureCallPattern {
    /// Returned values from completed matching calls.
    public func results() -> [Result] { base.results() }

    /// Errors thrown by completed matching calls.
    public func errors() -> [any Error] { base.errors() }

    /// Completion states for matching calls.
    public func outcomes() -> [InvocationOutcome<Result>] { base.outcomes() }

    /// The most recently entered matching call's completion state.
    public var lastOutcome: InvocationOutcome<Result>? { base.lastOutcome }
}

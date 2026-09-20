// Interaction members shared with `CallPattern` but previously reachable only
// on protocol doubles. Closure patterns own the same recorder and recording,
// so each member forwards to the identical implementation.

extension ClosureCallPattern {
    /// Interactions delegated to a forwarding target rather than answered by
    /// configured behavior.
    public var forwarded: CallInteractions { base.forwarded }

    /// Interactions answered by configured behavior rather than delegated to
    /// a forwarding target.
    public var stubbed: CallInteractions { base.stubbed }

    /// Errors of `Failure` thrown by completed matching calls.
    public func errors<Failure: Error>(ofType type: Failure.Type) -> [Failure] {
        base.errors(ofType: type)
    }

    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        _ = base.captureCallStacks(maxFrames: maxFrames)
        return self
    }

    /// Waits up to `timeout` for `count` matching calls to complete.
    public func waitForCompletion(
        count: Int = 1,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.waitForCompletion(
            count: count,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension ThrowingClosureCallPattern {
    /// Interactions delegated to a forwarding target rather than answered by
    /// configured behavior.
    public var forwarded: CallInteractions { base.forwarded }

    /// Interactions answered by configured behavior rather than delegated to
    /// a forwarding target.
    public var stubbed: CallInteractions { base.stubbed }

    /// Errors of `Failure` thrown by completed matching calls.
    public func errors<Failure: Error>(ofType type: Failure.Type) -> [Failure] {
        base.errors(ofType: type)
    }

    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        _ = base.captureCallStacks(maxFrames: maxFrames)
        return self
    }

    /// Waits up to `timeout` for `count` matching calls to complete.
    public func waitForCompletion(
        count: Int = 1,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.waitForCompletion(
            count: count,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension AsyncClosureCallPattern {
    /// Interactions delegated to a forwarding target rather than answered by
    /// configured behavior.
    public var forwarded: CallInteractions { base.forwarded }

    /// Interactions answered by configured behavior rather than delegated to
    /// a forwarding target.
    public var stubbed: CallInteractions { base.stubbed }

    /// Errors of `Failure` thrown by completed matching calls.
    public func errors<Failure: Error>(ofType type: Failure.Type) -> [Failure] {
        base.errors(ofType: type)
    }

    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        _ = base.captureCallStacks(maxFrames: maxFrames)
        return self
    }

    /// Waits up to `timeout` for `count` matching calls to complete.
    public func waitForCompletion(
        count: Int = 1,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.waitForCompletion(
            count: count,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Interactions delegated to a forwarding target rather than answered by
    /// configured behavior.
    public var forwarded: CallInteractions { base.forwarded }

    /// Interactions answered by configured behavior rather than delegated to
    /// a forwarding target.
    public var stubbed: CallInteractions { base.stubbed }

    /// Errors of `Failure` thrown by completed matching calls.
    public func errors<Failure: Error>(ofType type: Failure.Type) -> [Failure] {
        base.errors(ofType: type)
    }

    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        _ = base.captureCallStacks(maxFrames: maxFrames)
        return self
    }

    /// Waits up to `timeout` for `count` matching calls to complete.
    public func waitForCompletion(
        count: Int = 1,
        within timeout: Duration,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        await base.waitForCompletion(
            count: count,
            within: timeout,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

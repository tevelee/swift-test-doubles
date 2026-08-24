extension Stub {
    /// Enables call-stack capture for subsequent invocations on this double.
    ///
    /// Capture is disabled by default because symbolizing a stack is
    /// comparatively expensive. Captured symbols appear on
    /// ``InteractionTimeline/Event/callStack``. WASI has no thread stack
    /// symbolization API, so enabling capture there is a no-op.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        recorder.captureCallStacks(maxFrames: maxFrames)
        return self
    }
}

extension ManualStub {
    /// Enables call-stack capture for subsequent invocations on this double.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        recorder.captureCallStacks(maxFrames: maxFrames)
        return self
    }
}

extension CallPattern {
    /// Enables double-wide call-stack capture for subsequent invocations.
    ///
    /// This convenience makes the option available to protocol and closure
    /// patterns alike.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        recorder.captureCallStacks(maxFrames: maxFrames)
        return self
    }
}

extension CallInteractions {
    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        recorder.captureCallStacks(maxFrames: maxFrames)
        return self
    }
}

extension ConfiguredCall {
    /// Enables double-wide call-stack capture for subsequent invocations.
    @discardableResult
    public func captureCallStacks(maxFrames: Int = 32) -> Self {
        recorder.captureCallStacks(maxFrames: maxFrames)
        return self
    }
}

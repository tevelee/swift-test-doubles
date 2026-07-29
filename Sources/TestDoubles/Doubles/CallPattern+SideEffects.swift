extension CallPattern {
    /// Runs `action` immediately before each matching call's selected answer.
    ///
    /// The hook is independent of the answer: it composes with fixed values,
    /// handlers, errors, suspension, and forwarding. Configure hooks before
    /// the terminal `then` method.
    @discardableResult
    public func beforeEachCall<each Argument>(
        _ action: @escaping @Sendable (repeat each Argument) -> Void
    ) -> Self {
        var effects = sideEffects
        let methodName = recording.name
        effects.before.append { arguments in
            invokeTypedHandler(
                action,
                with: arguments,
                method: methodName,
                context: "Pre-call side effect"
            )
        }
        return Self(
            recorder: recorder,
            recording: recording,
            origin: origin,
            sideEffects: effects
        )
    }

    /// Runs `action` after each matching call completes.
    ///
    /// The hook runs after a return, throw, or completed spy delegation. It
    /// does not run for an invocation that remains suspended forever.
    @discardableResult
    public func afterEachCall<each Argument>(
        _ action: @escaping @Sendable (repeat each Argument) -> Void
    ) -> Self {
        var effects = sideEffects
        let methodName = recording.name
        effects.after.append { arguments in
            invokeTypedHandler(
                action,
                with: arguments,
                method: methodName,
                context: "Post-call side effect"
            )
        }
        return Self(
            recorder: recorder,
            recording: recording,
            origin: origin,
            sideEffects: effects
        )
    }
}

extension ClosureCallPattern {
    /// Adds a pre-call side effect without replacing the configured answer.
    public func beforeEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.beforeEachCall(action))
    }

    /// Adds a post-call side effect without replacing the configured answer.
    public func afterEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.afterEachCall(action))
    }
}

extension ThrowingClosureCallPattern {
    /// Adds a pre-call side effect without replacing the configured answer.
    public func beforeEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.beforeEachCall(action))
    }

    /// Adds a post-call side effect without replacing the configured answer.
    public func afterEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.afterEachCall(action))
    }
}

extension AsyncClosureCallPattern {
    /// Adds a pre-call side effect without replacing the configured answer.
    public func beforeEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.beforeEachCall(action))
    }

    /// Adds a post-call side effect without replacing the configured answer.
    public func afterEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.afterEachCall(action))
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Adds a pre-call side effect without replacing the configured answer.
    public func beforeEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.beforeEachCall(action))
    }

    /// Adds a post-call side effect without replacing the configured answer.
    public func afterEachCall(
        _ action: @escaping @Sendable (Input) -> Void
    ) -> Self {
        Self(base: base.afterEachCall(action))
    }
}

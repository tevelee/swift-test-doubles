#if RUNTIME_STUB
/// Configures the return value or action for a stubbed method.
/// Returned by ``RuntimeStub/when(_:)-4hxsd``.
public struct StubBuilder<R> {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Return a static value.
    /// ```swift
    /// stub.when { $0.find(id: any()) }.returns("Alice")
    /// ```
    @discardableResult
    public func returns(_ value: @autoclosure @escaping () -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { _ in value() })
        return self
    }

    /// Unified stub handler — can return values or throw errors.
    /// ```swift
    /// stub.when { try $0.read(path: any()) }.then { "content" }
    /// stub.when { try $0.read(path: any()) }.then { throw NotFoundError() }
    /// stub.when { try $0.read(path: any()) }.then { args in "path: \(args[0])" }
    /// ```
    @discardableResult
    public func then(_ handler: @escaping ([Any]) throws -> R) -> Self {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        recorder.addThrowingStub(method: recording.methodIndex, matchers: matchers, handler: handler)
        recorder.addStub(method: recording.methodIndex, matchers: matchers, returnValue: { args in
            try! handler(args)
        })
        return self
    }

    /// Convenience: no-args handler.
    /// ```swift
    /// stub.when { try $0.read(path: any()) }.then { "content" }
    /// stub.when { try $0.read(path: any()) }.then { throw NotFoundError() }
    /// ```
    @discardableResult
    public func then(_ handler: @escaping () throws -> R) -> Self {
        then { _ in try handler() }
    }

    /// Typed one-argument handler.
    /// ```swift
    /// stub.when { $0.find(id: any()) }.then { (id: Int) in "user_\(id)" }
    /// ```
    @discardableResult
    public func then<A>(_ handler: @escaping (A) throws -> R) -> Self {
        then { args in
            try handler(typedArgument(A.self, from: args, at: 0, method: recording.name))
        }
    }

    /// Typed two-argument handler.
    @discardableResult
    public func then<A, B>(_ handler: @escaping (A, B) throws -> R) -> Self {
        then { args in
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name),
                typedArgument(B.self, from: args, at: 1, method: recording.name)
            )
        }
    }

    /// Typed three-argument handler.
    @discardableResult
    public func then<A, B, C>(_ handler: @escaping (A, B, C) throws -> R) -> Self {
        then { args in
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name),
                typedArgument(B.self, from: args, at: 1, method: recording.name),
                typedArgument(C.self, from: args, at: 2, method: recording.name)
            )
        }
    }

    /// Typed four-argument handler.
    @discardableResult
    public func then<A, B, C, D>(_ handler: @escaping (A, B, C, D) throws -> R) -> Self {
        then { args in
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name),
                typedArgument(B.self, from: args, at: 1, method: recording.name),
                typedArgument(C.self, from: args, at: 2, method: recording.name),
                typedArgument(D.self, from: args, at: 3, method: recording.name)
            )
        }
    }

    /// Typed five-argument handler.
    @discardableResult
    public func then<A, B, C, D, E>(_ handler: @escaping (A, B, C, D, E) throws -> R) -> Self {
        then { args in
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name),
                typedArgument(B.self, from: args, at: 1, method: recording.name),
                typedArgument(C.self, from: args, at: 2, method: recording.name),
                typedArgument(D.self, from: args, at: 3, method: recording.name),
                typedArgument(E.self, from: args, at: 4, method: recording.name)
            )
        }
    }

    /// Typed six-argument handler.
    @discardableResult
    public func then<A, B, C, D, E, F>(_ handler: @escaping (A, B, C, D, E, F) throws -> R) -> Self {
        then { args in
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name),
                typedArgument(B.self, from: args, at: 1, method: recording.name),
                typedArgument(C.self, from: args, at: 2, method: recording.name),
                typedArgument(D.self, from: args, at: 3, method: recording.name),
                typedArgument(E.self, from: args, at: 4, method: recording.name),
                typedArgument(F.self, from: args, at: 5, method: recording.name)
            )
        }
    }
}

/// Asserts that a stubbed method was called the expected number of times.
/// Returned by ``RuntimeStub/verify(_:)-6f6ij``.
public struct VerifyBuilder {
    let recorder: StubRecorder
    let recording: RecordedCall

    /// Assert the method was called (at least once, or exactly `times` times).
    public func wasCalled(times: Int? = nil) {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        let count = recorder.callCount(method: recording.methodIndex, matchers: matchers)
        if let expected = times {
            precondition(count == expected,
                "'\(recording.name)': expected \(expected) call(s), got \(count)")
        } else {
            precondition(count > 0,
                "'\(recording.name)': expected at least 1 call, got 0")
        }
    }

    /// Assert the method was never called.
    public func wasNotCalled() { wasCalled(times: 0) }

    /// Inspect arguments of matching calls.
    /// ```swift
    /// stub.verify { $0.find(id: any()) }.withArgs { calls in
    ///     XCTAssertEqual(calls[0][0] as! Int, 42)
    /// }
    /// ```
    public func withArgs(_ handler: ([[Any]]) throws -> Void) rethrows {
        try handler(matchingArguments())
    }

    /// Inspects each matching call with one typed argument.
    public func withArgs<A>(_ handler: (A) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"))
        }
    }

    /// Inspects each matching call with two typed arguments.
    public func withArgs<A, B>(_ handler: (A, B) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(B.self, from: args, at: 1, method: recording.name, context: "Typed withArgs handler")
            )
        }
    }

    /// Inspects each matching call with three typed arguments.
    public func withArgs<A, B, C>(_ handler: (A, B, C) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(B.self, from: args, at: 1, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(C.self, from: args, at: 2, method: recording.name, context: "Typed withArgs handler")
            )
        }
    }

    /// Inspects each matching call with four typed arguments.
    public func withArgs<A, B, C, D>(_ handler: (A, B, C, D) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(B.self, from: args, at: 1, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(C.self, from: args, at: 2, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(D.self, from: args, at: 3, method: recording.name, context: "Typed withArgs handler")
            )
        }
    }

    /// Inspects each matching call with five typed arguments.
    public func withArgs<A, B, C, D, E>(_ handler: (A, B, C, D, E) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(B.self, from: args, at: 1, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(C.self, from: args, at: 2, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(D.self, from: args, at: 3, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(E.self, from: args, at: 4, method: recording.name, context: "Typed withArgs handler")
            )
        }
    }

    /// Inspects each matching call with six typed arguments.
    public func withArgs<A, B, C, D, E, F>(_ handler: (A, B, C, D, E, F) throws -> Void) rethrows {
        for args in matchingArguments() {
            try handler(
                typedArgument(A.self, from: args, at: 0, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(B.self, from: args, at: 1, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(C.self, from: args, at: 2, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(D.self, from: args, at: 3, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(E.self, from: args, at: 4, method: recording.name, context: "Typed withArgs handler"),
                typedArgument(F.self, from: args, at: 5, method: recording.name, context: "Typed withArgs handler")
            )
        }
    }

    private func matchingArguments() -> [[Any]] {
        let matchers = recording.matchers.isEmpty
            ? recording.args.map { DescriptionMatcher(value: $0) }
            : recording.matchers
        let matching = recorder.calls.filter { call in
            call.methodIndex == recording.methodIndex &&
            (matchers.isEmpty || matchArgs(call.args, against: matchers))
        }
        return matching.map(\.args)
    }

    private func matchArgs(_ args: [Any], against matchers: [ParameterMatcher]) -> Bool {
        guard args.count == matchers.count else { return matchers.isEmpty }
        return zip(args, matchers).allSatisfy { $0.1.matches(value: $0.0) }
    }
}
#endif // RUNTIME_STUB

// MARK: - Arbitrary-arity function adapters

extension ClosureDouble {
    /// Adapts a tuple-input closure double to a function of arbitrary arity.
    ///
    /// Declare `Input` as the tuple of function arguments, then use the
    /// contextual function type to infer and expand its elements:
    ///
    /// ```swift
    /// let double = ClosureDouble<(Int, String), String>()
    /// let function: (Int, String) -> String = double.expandedFunction()
    /// ```
    public func expandedFunction<each Argument>()
        -> (repeat each Argument) -> Result
    where Input == (repeat each Argument) {
        { (argument: repeat each Argument) in
            self((repeat each argument))
        }
    }

    /// Invokes a tuple-input closure double with separate arguments.
    public func invoke<each Argument>(
        _ argument: repeat each Argument
    ) -> Result
    where Input == (repeat each Argument) {
        self((repeat each argument))
    }

    /// Starts a registration selected by a predicate over separate arguments.
    public func whenArguments<each Argument>(
        _ matcher: @escaping @Sendable (repeat each Argument) -> Bool,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ClosureCallPattern<Input, Result>
    where Input == (repeat each Argument) {
        when(
            { input in matcher(repeat each input) },
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension ThrowingClosureDouble {
    /// Adapts a tuple-input throwing closure double to a function of arbitrary
    /// arity.
    public func expandedFunction<each Argument>()
        -> (repeat each Argument) throws -> Result
    where Input == (repeat each Argument) {
        { (argument: repeat each Argument) in
            try self((repeat each argument))
        }
    }

    /// Invokes a tuple-input throwing closure double with separate arguments.
    public func invoke<each Argument>(
        _ argument: repeat each Argument
    ) throws -> Result
    where Input == (repeat each Argument) {
        try self((repeat each argument))
    }

    /// Starts a registration selected by a predicate over separate arguments.
    public func whenArguments<each Argument>(
        _ matcher: @escaping @Sendable (repeat each Argument) -> Bool,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> ThrowingClosureCallPattern<Input, Result>
    where Input == (repeat each Argument) {
        when(
            { input in matcher(repeat each input) },
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension AsyncClosureDouble {
    /// Adapts a tuple-input asynchronous closure double to a function of
    /// arbitrary arity.
    public func expandedFunction<each Argument>()
        -> (repeat each Argument) async -> Result
    where Input == (repeat each Argument) {
        { (argument: repeat each Argument) in
            await self((repeat each argument))
        }
    }

    /// Invokes a tuple-input asynchronous closure double with separate
    /// arguments.
    public func invoke<each Argument>(
        _ argument: repeat each Argument
    ) async -> Result
    where Input == (repeat each Argument) {
        await self((repeat each argument))
    }

    /// Starts a registration selected by a predicate over separate arguments.
    public func whenArguments<each Argument>(
        _ matcher: @escaping @Sendable (repeat each Argument) -> Bool,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncClosureCallPattern<Input, Result>
    where Input == (repeat each Argument) {
        when(
            { input in matcher(repeat each input) },
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

extension AsyncThrowingClosureDouble {
    /// Adapts a tuple-input asynchronous throwing closure double to a function
    /// of arbitrary arity.
    public func expandedFunction<each Argument>()
        -> (repeat each Argument) async throws -> Result
    where Input == (repeat each Argument) {
        { (argument: repeat each Argument) in
            try await self((repeat each argument))
        }
    }

    /// Invokes a tuple-input asynchronous throwing closure double with separate
    /// arguments.
    public func invoke<each Argument>(
        _ argument: repeat each Argument
    ) async throws -> Result
    where Input == (repeat each Argument) {
        try await self((repeat each argument))
    }

    /// Starts a registration selected by a predicate over separate arguments.
    public func whenArguments<each Argument>(
        _ matcher: @escaping @Sendable (repeat each Argument) -> Bool,
        describedBy description: String = "predicate",
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) -> AsyncThrowingClosureCallPattern<Input, Result>
    where Input == (repeat each Argument) {
        when(
            { input in matcher(repeat each input) },
            describedBy: description,
            fileID: fileID,
            filePath: filePath,
            line: line,
            column: column
        )
    }
}

// MARK: - Typed behavior adapters

extension ClosureCallPattern {
    /// Computes `times` matching results from separate typed arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (repeat each Argument) -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            handler(repeat each input)
        }
    }

    /// Computes every matching result from separate typed arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (repeat each Argument) -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            handler(repeat each input)
        }
    }

    /// Computes `times` matching results from a call count and separate
    /// arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCallArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping @Sendable (
                Int,
                repeat each Argument
            ) -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            handler(count, repeat each input)
        }
    }

    /// Computes every matching result from a call count and separate
    /// arguments.
    @discardableResult
    public func thenForEachCallArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping @Sendable (
                Int,
                repeat each Argument
            ) -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            handler(count, repeat each input)
        }
    }
}

extension ThrowingClosureCallPattern {
    /// Computes `times` matching results from separate typed arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping @Sendable (
                repeat each Argument
            ) throws -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try handler(repeat each input)
        }
    }

    /// Computes every matching result from separate typed arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping @Sendable (
                repeat each Argument
            ) throws -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try handler(repeat each input)
        }
    }

    /// Computes `times` matching results from a call count and separate
    /// arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCallArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping @Sendable (
                Int,
                repeat each Argument
            ) throws -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            try handler(count, repeat each input)
        }
    }

    /// Computes every matching result from a call count and separate
    /// arguments.
    @discardableResult
    public func thenForEachCallArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping @Sendable (
                Int,
                repeat each Argument
            ) throws -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            try handler(count, repeat each input)
        }
    }
}

extension AsyncClosureCallPattern {
    /// Immediately computes `times` matching results from separate arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler: @escaping @Sendable (repeat each Argument) -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            handler(repeat each input)
        }
    }

    /// Immediately computes every matching result from separate arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping @Sendable (repeat each Argument) -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            handler(repeat each input)
        }
    }

    /// Asynchronously computes `times` matching results from separate
    /// arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler: @escaping (repeat each Argument) async -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            await handler(repeat each input)
        }
    }

    /// Asynchronously computes every matching result from separate arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler: @escaping (repeat each Argument) async -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            await handler(repeat each input)
        }
    }

    /// Asynchronously computes `times` matching results from a call count and
    /// separate arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCallArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping (
                Int,
                repeat each Argument
            ) async -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            await handler(count, repeat each input)
        }
    }

    /// Asynchronously computes every matching result from a call count and
    /// separate arguments.
    @discardableResult
    public func thenForEachCallArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping (
                Int,
                repeat each Argument
            ) async -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            await handler(count, repeat each input)
        }
    }
}

extension AsyncThrowingClosureCallPattern {
    /// Immediately computes `times` matching results from separate arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping @Sendable (
                repeat each Argument
            ) throws -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try handler(repeat each input)
        }
    }

    /// Immediately computes every matching result from separate arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping @Sendable (
                repeat each Argument
            ) throws -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try handler(repeat each input)
        }
    }

    /// Asynchronously computes `times` matching results from separate
    /// arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping (
                repeat each Argument
            ) async throws -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try await handler(repeat each input)
        }
    }

    /// Asynchronously computes every matching result from separate arguments.
    @discardableResult
    public func thenArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping (
                repeat each Argument
            ) async throws -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        then(times: times) { (input: Input) in
            try await handler(repeat each input)
        }
    }

    /// Asynchronously computes `times` matching results from a call count and
    /// separate arguments.
    @discardableResult
    @_disfavoredOverload
    public func thenForEachCallArguments<each Argument>(
        times: Int = 1,
        _ handler:
            @escaping (
                Int,
                repeat each Argument
            ) async throws -> Result
    ) -> StubBehaviorChain<Result>
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            try await handler(count, repeat each input)
        }
    }

    /// Asynchronously computes every matching result from a call count and
    /// separate arguments.
    @discardableResult
    public func thenForEachCallArguments<each Argument>(
        times: PartialRangeFrom<Int> = 1...,
        _ handler:
            @escaping (
                Int,
                repeat each Argument
            ) async throws -> Result
    ) -> CallInteractions
    where Input == (repeat each Argument) {
        thenForEachCall(times: times) { (count: Int, input: Input) in
            try await handler(count, repeat each input)
        }
    }
}

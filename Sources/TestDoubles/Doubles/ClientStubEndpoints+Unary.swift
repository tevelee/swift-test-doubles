extension ClientStubEndpoints {
    /// Creates a synchronous endpoint for a closure field with exactly one
    /// parameter.
    ///
    /// The variadic ``function(_:)`` covers every arity, but Swift 6.3 and 6.4
    /// crash while compiling it for a field whose single parameter is a tuple,
    /// such as `@Sendable ((Int, Int)) -> Int`. This fixed-arity form binds
    /// the tuple as one argument and records it as a tuple:
    ///
    /// ```swift
    /// struct Geometry {
    ///     var area: @Sendable ((width: Int, height: Int)) -> Int
    /// }
    ///
    /// let geometry = ClientStub<Geometry> { endpoints in
    ///     Geometry(area: endpoints.unaryFunction("area"))
    /// }
    /// geometry.when { $0.area(Match.any()) }.then { (size: (width: Int, height: Int)) in
    ///     size.width * size.height
    /// }
    /// ```
    public func unaryFunction<Argument, Result>(
        _ name: String
    ) -> @Sendable (Argument) -> Result {
        // Inside this generic context the single pack element stays opaque,
        // which avoids the compiler's tuple reabstraction crash.
        function(name)
    }

    /// Creates a synchronous throwing endpoint for a closure field with exactly
    /// one parameter. See ``unaryFunction(_:)``.
    public func unaryThrowingFunction<Argument, Result>(
        _ name: String
    ) -> @Sendable (Argument) throws -> Result {
        throwingFunction(name)
    }

    /// Creates an asynchronous endpoint for a closure field with exactly one
    /// parameter. See ``unaryFunction(_:)``.
    public func unaryAsyncFunction<Argument, Result>(
        _ name: String
    ) -> @Sendable (Argument) async -> Result {
        asyncFunction(name)
    }

    /// Creates an asynchronous throwing endpoint for a closure field with
    /// exactly one parameter. See ``unaryFunction(_:)``.
    public func unaryAsyncThrowingFunction<Argument, Result>(
        _ name: String
    ) -> @Sendable (Argument) async throws -> Result {
        asyncThrowingFunction(name)
    }
}

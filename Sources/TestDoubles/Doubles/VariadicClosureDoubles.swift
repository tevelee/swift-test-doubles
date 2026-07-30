/// A closure double whose injected function accepts zero or more homogeneous
/// arguments.
///
/// Each invocation is recorded as one `[Element]` input, so existing matching,
/// behavior, history, streaming, and forwarding APIs remain available.
public typealias VariadicClosureDouble<Element, Result> =
    ClosureDouble<[Element], Result>

/// A throwing closure double whose injected function accepts zero or more
/// homogeneous arguments.
public typealias VariadicThrowingClosureDouble<Element, Result> =
    ThrowingClosureDouble<[Element], Result>

/// An asynchronous closure double whose injected function accepts zero or more
/// homogeneous arguments.
public typealias VariadicAsyncClosureDouble<Element, Result> =
    AsyncClosureDouble<[Element], Result>

/// An asynchronous throwing closure double whose injected function accepts
/// zero or more homogeneous arguments.
public typealias VariadicAsyncThrowingClosureDouble<Element, Result> =
    AsyncThrowingClosureDouble<[Element], Result>

/// A typed-throws closure double whose injected function accepts zero or more
/// homogeneous arguments.
public typealias VariadicTypedThrowingClosureDouble<
    Element,
    Result,
    Failure: Error
> = TypedThrowingClosureDouble<[Element], Result, Failure>

/// An asynchronous typed-throws closure double whose injected function accepts
/// zero or more homogeneous arguments.
public typealias VariadicAsyncTypedThrowingClosureDouble<
    Element,
    Result,
    Failure: Error
> = AsyncTypedThrowingClosureDouble<[Element], Result, Failure>

/// A closure double with a heterogeneous parameter pack.
///
/// List the function's argument types first and its result type last, then use
/// ``ClosureDouble/expandedFunction()`` to obtain the callable value.
public typealias ParameterPackClosureDouble<each Argument, Result> =
    ClosureDouble<(repeat each Argument), Result>

/// A throwing closure double with a heterogeneous parameter pack.
public typealias ParameterPackThrowingClosureDouble<each Argument, Result> =
    ThrowingClosureDouble<(repeat each Argument), Result>

/// An asynchronous closure double with a heterogeneous parameter pack.
public typealias ParameterPackAsyncClosureDouble<each Argument, Result> =
    AsyncClosureDouble<(repeat each Argument), Result>

/// An asynchronous throwing closure double with a heterogeneous parameter
/// pack.
public typealias ParameterPackAsyncThrowingClosureDouble<
    each Argument,
    Result
> = AsyncThrowingClosureDouble<(repeat each Argument), Result>

/// A typed-throws closure double with a heterogeneous parameter pack.
public typealias ParameterPackTypedThrowingClosureDouble<
    each Argument,
    Result,
    Failure: Error
> = TypedThrowingClosureDouble<
    (repeat each Argument),
    Result,
    Failure
>

/// An asynchronous typed-throws closure double with a heterogeneous parameter
/// pack.
public typealias ParameterPackAsyncTypedThrowingClosureDouble<
    each Argument,
    Result,
    Failure: Error
> = AsyncTypedThrowingClosureDouble<
    (repeat each Argument),
    Result,
    Failure
>

extension ClosureDouble {
    /// Adapts an array-input double to a homogeneous variadic function.
    public func variadicFunction<Element>() -> (Element...) -> Result
    where Input == [Element] {
        { elements in
            self(elements)
        }
    }

    /// Invokes an array-input double using homogeneous variadic arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) -> Result where Input == [Element] {
        self(elements)
    }
}

extension ThrowingClosureDouble {
    /// Adapts an array-input double to a throwing homogeneous variadic
    /// function.
    public func variadicFunction<Element>()
        -> (Element...) throws -> Result
    where Input == [Element] {
        { elements in
            try self(elements)
        }
    }

    /// Invokes an array-input throwing double using homogeneous variadic
    /// arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) throws -> Result where Input == [Element] {
        try self(elements)
    }
}

extension AsyncClosureDouble {
    /// Adapts an array-input double to an asynchronous homogeneous variadic
    /// function.
    public func variadicFunction<Element>()
        -> (Element...) async -> Result
    where Input == [Element] {
        { elements in
            await self(elements)
        }
    }

    /// Invokes an array-input asynchronous double using homogeneous variadic
    /// arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) async -> Result where Input == [Element] {
        await self(elements)
    }
}

extension AsyncThrowingClosureDouble {
    /// Adapts an array-input double to an asynchronous throwing homogeneous
    /// variadic function.
    public func variadicFunction<Element>()
        -> (Element...) async throws -> Result
    where Input == [Element] {
        { elements in
            try await self(elements)
        }
    }

    /// Invokes an array-input asynchronous throwing double using homogeneous
    /// variadic arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) async throws -> Result where Input == [Element] {
        try await self(elements)
    }
}

extension TypedThrowingClosureDouble {
    /// Adapts an array-input double to a typed-throws homogeneous variadic
    /// function.
    public func variadicFunction<Element>()
        -> (Element...) throws(Failure) -> Result
    where Input == [Element] {
        { elements throws(Failure) in
            try self(elements)
        }
    }

    /// Invokes an array-input typed-throws double using homogeneous variadic
    /// arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) throws(Failure) -> Result where Input == [Element] {
        try self(elements)
    }
}

extension AsyncTypedThrowingClosureDouble {
    /// Adapts an array-input double to an asynchronous typed-throws
    /// homogeneous variadic function.
    public func variadicFunction<Element>()
        -> (Element...) async throws(Failure) -> Result
    where Input == [Element] {
        { elements async throws(Failure) in
            try await self(elements)
        }
    }

    /// Invokes an array-input asynchronous typed-throws double using
    /// homogeneous variadic arguments.
    public func invokeVariadic<Element>(
        _ elements: Element...
    ) async throws(Failure) -> Result where Input == [Element] {
        try await self(elements)
    }
}

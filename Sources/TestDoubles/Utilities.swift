/// Creates a zero-initialized value of any type.
func zeroValue<V>(_ type: V.Type = V.self) -> V {
    let size = MemoryLayout<V>.size
    guard size > 0 else {
        return unsafeBitCast((), to: V.self)
    }
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<V>.alignment)
    defer { ptr.deallocate() }
    ptr.initializeMemory(as: UInt8.self, repeating: 0, count: size)
    return ptr.load(as: V.self)
}

func typedArgument<T>(
    _ type: T.Type,
    from args: [Any],
    at index: Int,
    method: String,
    context: String = "Typed argument handler"
) -> T {
    guard args.indices.contains(index) else {
        preconditionFailure("[TestDoubles] \(context) for '\(method)' expected argument \(index), but the call had \(args.count) argument(s).")
    }
    guard let value = args[index] as? T else {
        preconditionFailure("[TestDoubles] \(context) for '\(method)' expected argument \(index) to be \(T.self), got \(Swift.type(of: args[index])).")
    }
    return value
}

/// Invokes a synchronous typed handler with arguments decoded from type-erased storage.
func invokeTypedHandler<each Argument, Result>(
    _ handler: (repeat each Argument) throws -> Result,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) rethrows -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try handler(repeat nextArgument((each Argument).self))
}

/// Invokes an asynchronous typed handler with arguments decoded from type-erased storage.
func invokeTypedHandler<each Argument, Result>(
    _ handler: (repeat each Argument) async throws -> Result,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) async rethrows -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try await handler(repeat nextArgument((each Argument).self))
}

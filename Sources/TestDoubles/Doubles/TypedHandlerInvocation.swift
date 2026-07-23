import Foundation

/// A thread-safe running count for a single stub registration, so an
/// attempt-aware handler can vary its response by how many matching calls it
/// has already served. Each registration owns its own counter, mirroring how
/// behavior chains advance independently per registration.
final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    /// Returns the 1-based index of this call among the matching calls this
    /// registration has served, including the current one.
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
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
func invokeTypedHandler<each Argument, Result, Failure: Error>(
    _ handler: @Sendable (repeat each Argument) throws(Failure) -> Result,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) throws(Failure) -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try handler(repeat nextArgument((each Argument).self))
}

/// Invokes an asynchronous typed handler with arguments decoded from type-erased storage.
func invokeTypedHandler<each Argument, Result, Failure: Error>(
    _ handler: (repeat each Argument) async throws(Failure) -> Result,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) async throws(Failure) -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try await handler(repeat nextArgument((each Argument).self))
}

/// Invokes a synchronous typed handler, passing a leading invocation count
/// ahead of the arguments decoded from type-erased storage.
func invokeCountingHandler<each Argument, Result, Failure: Error>(
    _ handler: @Sendable (Int, repeat each Argument) throws(Failure) -> Result,
    count: Int,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) throws(Failure) -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try handler(count, repeat nextArgument((each Argument).self))
}

/// Invokes an asynchronous typed handler, passing a leading invocation count
/// ahead of the arguments decoded from type-erased storage.
func invokeCountingHandler<each Argument, Result, Failure: Error>(
    _ handler: (Int, repeat each Argument) async throws(Failure) -> Result,
    count: Int,
    with args: [Any],
    method: String,
    context: String = "Typed argument handler"
) async throws(Failure) -> Result {
    var index = 0

    func nextArgument<T>(_ type: T.Type) -> T {
        defer { index += 1 }
        return typedArgument(type, from: args, at: index, method: method, context: context)
    }

    return try await handler(count, repeat nextArgument((each Argument).self))
}

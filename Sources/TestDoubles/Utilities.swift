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

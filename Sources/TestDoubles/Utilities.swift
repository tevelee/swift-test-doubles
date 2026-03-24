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

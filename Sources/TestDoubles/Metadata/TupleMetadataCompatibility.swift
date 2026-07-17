import Echo

extension TupleMetadata {
    /// Avoids Echo 0.0.4's `Array(unsafeUninitializedCapacity: 0)` path for
    /// `Void`, which mutates Swift's shared empty-array storage and races when
    /// multiple stubs inspect metadata concurrently.
    var safelyInitializedElements: [Element] {
        numElements == 0 ? [] : elements
    }
}

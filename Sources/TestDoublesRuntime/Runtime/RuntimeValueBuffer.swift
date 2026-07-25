import Echo

extension Metadata {
    /// The byte count of temporary storage for one value of this type, padded
    /// to `minimum` bytes so register-word codecs may address whole words.
    package func valueBufferByteCount(minimum: Int = 1) -> Int {
        max(vwt.size, minimum)
    }

    /// Allocates uninitialized temporary storage for one value of this type,
    /// word-aligned so register-word codecs may address whole words. The
    /// caller owns deinitialization and deallocation.
    package func allocateValueBuffer(minimumByteCount: Int = 1) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer.allocate(
            byteCount: valueBufferByteCount(minimum: minimumByteCount),
            alignment: max(vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        )
    }
}

/// Tracks whether raw value storage is uninitialized, merely borrows ABI
/// bits, owns an initialized value, or has transferred that ownership.
///
/// Owned allocations are always deallocated. Only an initialized owned value
/// is destroyed; borrowed and transferred bits are never destroyed here.
package final class ManagedValueBuffer: @unchecked Sendable {
    package enum State: Equatable, Sendable {
        case uninitialized
        case borrowedBits
        case initialized
        case transferred
    }

    package let metadata: Metadata
    package let storage: UnsafeMutableRawPointer
    package private(set) var state: State

    private let byteCount: Int
    private let deallocatesStorage: Bool

    package init(type: Any.Type, minimumByteCount: Int = 1) {
        metadata = reflect(type)
        byteCount = metadata.valueBufferByteCount(minimum: minimumByteCount)
        storage = metadata.allocateValueBuffer(
            minimumByteCount: minimumByteCount
        )
        state = .uninitialized
        deallocatesStorage = true
    }

    /// Creates a non-owning view of initialized ABI bits. The referenced value
    /// remains owned by the caller and is never destroyed by this view.
    package init(
        borrowingBitsOf type: Any.Type,
        at storage: UnsafeMutableRawPointer
    ) {
        metadata = reflect(type)
        self.storage = storage
        state = .borrowedBits
        byteCount = metadata.valueBufferByteCount()
        deallocatesStorage = false
    }

    /// Creates a non-allocating owner for a value whose initialized storage
    /// must be consumed exactly once without deallocating the caller's bytes.
    package init(
        owningValueOf type: Any.Type,
        at storage: UnsafeMutableRawPointer
    ) {
        metadata = reflect(type)
        self.storage = storage
        state = .initialized
        byteCount = metadata.valueBufferByteCount()
        deallocatesStorage = false
    }

    package func zeroBorrowedBytes() {
        precondition(state == .uninitialized)
        storage.initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: byteCount
        )
        state = .borrowedBits
    }

    package func markInitialized() {
        precondition(state == .uninitialized || state == .borrowedBits)
        state = .initialized
    }

    package func destroyInitializedValue() {
        precondition(state == .initialized)
        metadata.vwt.destroy(storage)
        state = .uninitialized
    }

    package func moveInitializedValue<Value>(as _: Value.Type) -> Value {
        precondition(state == .initialized)
        precondition(
            ObjectIdentifier(Value.self) == ObjectIdentifier(metadata.type),
            "[TestDoubles] Managed value storage was moved as the wrong type."
        )
        let value = storage.assumingMemoryBound(to: Value.self).move()
        state = .transferred
        return value
    }

    package func markTransferred() {
        precondition(state == .initialized)
        state = .transferred
    }

    deinit {
        if state == .initialized {
            metadata.vwt.destroy(storage)
        }
        if deallocatesStorage {
            storage.deallocate()
        }
    }
}

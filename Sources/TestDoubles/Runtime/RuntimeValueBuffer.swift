import Echo

extension Metadata {
    /// The byte count of temporary storage for one value of this type, padded
    /// to `minimum` bytes so register-word codecs may address whole words.
    func valueBufferByteCount(minimum: Int = 1) -> Int {
        max(vwt.size, minimum)
    }

    /// Allocates uninitialized temporary storage for one value of this type,
    /// word-aligned so register-word codecs may address whole words. The
    /// caller owns deinitialization and deallocation.
    func allocateValueBuffer(minimumByteCount: Int = 1) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer.allocate(
            byteCount: valueBufferByteCount(minimum: minimumByteCount),
            alignment: max(vwt.flags.alignment, MemoryLayout<UInt>.alignment)
        )
    }
}

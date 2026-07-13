#if RUNTIME_STUB
import Echo
import Foundation

/// Maps per-mock context keys to their stub recorders.
/// For thunk-backed mocks, the witness table pointer is the natural key.
/// For runtime-compiled mocks, the inline `_ctx` field provides the key.
///
/// Both backends ultimately hand a stable pointer to `MockBridge` or a thunk,
/// so the registry can stay agnostic about how that key was produced.
enum MockRegistry {
    nonisolated(unsafe) private static var storage: [UnsafeRawPointer: StubRecorder] = [:]
    private static let lock = NSLock()

    static func register(_ recorder: StubRecorder, for key: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = recorder
    }

    static func remove(for key: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    /// Resolve a recorder without trapping when the owning stub is gone.
    @inline(__always)
    static func resolveOptional(_ key: UnsafeRawPointer) -> StubRecorder? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
#endif

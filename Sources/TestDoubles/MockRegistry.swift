import Echo
import Foundation

/// Maps per-mock context keys to their stub recorders.
/// For thunk-backed mocks, the witness table pointer is the natural key.
/// For runtime-compiled mocks, the inline `_ctx` field provides the key.
///
/// Both backends ultimately hand a stable pointer to `MockBridge` or a thunk,
/// so the registry can stay agnostic about how that key was produced.
public enum MockRegistry {
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

    /// Called by thunks and bridge functions to resolve the recorder from the context key.
    @inline(__always)
    public static func resolve(_ key: UnsafeRawPointer) -> StubRecorder {
        lock.lock()
        defer { lock.unlock() }
        guard let recorder = storage[key] else {
            fatalError("No mock registered for context key \(key)")
        }
        return recorder
    }

    /// Non-fatal resolve — returns nil if not found (used by bridge functions).
    @inline(__always)
    public static func resolveOptional(_ key: UnsafeRawPointer) -> StubRecorder? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}

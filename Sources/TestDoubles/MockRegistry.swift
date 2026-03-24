import Echo
import Foundation

/// Maps witness table pointers to their mock contexts.
/// Each mock gets a uniquely allocated witness table, making the
/// witness table pointer a natural per-mock identifier.
///
/// The `wtPtr` argument (last parameter in every witness thunk) is used
/// as the lookup key — this works for both struct and class existentials.
public enum MockRegistry {
    nonisolated(unsafe) private static var storage: [UnsafeRawPointer: StubRecorder] = [:]
    private static let lock = NSLock()

    static func register(_ recorder: StubRecorder, for witnessTable: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        storage[witnessTable] = recorder
    }

    static func remove(for witnessTable: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: witnessTable)
    }

    /// Called by thunks to resolve the recorder from the witness table pointer.
    @inline(__always)
    public static func resolve(_ wtPtr: UnsafeRawPointer) -> StubRecorder {
        lock.lock()
        defer { lock.unlock() }
        guard let recorder = storage[wtPtr] else {
            fatalError("No mock registered for witness table at \(wtPtr)")
        }
        return recorder
    }

    /// Non-fatal resolve — returns nil if not found (used by bridge functions).
    @inline(__always)
    public static func resolveOptional(_ wtPtr: UnsafeRawPointer) -> StubRecorder? {
        lock.lock()
        defer { lock.unlock() }
        return storage[wtPtr]
    }
}

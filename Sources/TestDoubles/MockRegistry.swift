import Foundation

/// Maps each fabricated witness table's stable context key to its recorder.
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

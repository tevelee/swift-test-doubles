import Foundation

/// Process-global factories for recording placeholder values.
///
/// The recording pass behind `when`, `verify`, and `invocations` closures
/// needs one valid temporary value per argument and result. TestDoubles
/// synthesizes most types; class instances, existentials, and other layouts
/// it cannot initialize safely normally take a value at each site through
/// the `using:` and `returning:` overloads. Registering a factory supplies
/// that value once for a whole suite instead:
///
/// ```swift
/// RecordingPlaceholders.register { User(name: "placeholder") }
///
/// // Every later recording of a User argument or result just works:
/// stub.when { $0.displayName(for: any()) }.thenReturn("Blob")
/// ```
///
/// A registered value is used only while recording. It is never matched
/// against, returned from a stubbed call, or retained past the recording
/// pass. Explicit `using:` and `returning:` values win over registered
/// factories, and registered factories win over synthesized values.
/// Factories match the exact registered type, so an existential and each
/// concrete class register separately.
///
/// The registry is shared by the whole test process. Register in suite-level
/// setup rather than in individual parallel tests, or `unregister` on the
/// way out.
public enum RecordingPlaceholders {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var factories: [ObjectIdentifier: @Sendable () -> Any] = [:]

    /// Registers `make` as the recording placeholder factory for `Value`.
    /// The most recent registration for a type wins.
    public static func register<Value>(
        _ type: Value.Type = Value.self,
        _ make: @escaping @Sendable () -> Value
    ) {
        lock.lock()
        defer { lock.unlock() }
        factories[ObjectIdentifier(type)] = { make() }
    }

    /// Removes the factory for `Value`, restoring the default synthesis and
    /// `using:`/`returning:` contract.
    public static func unregister<Value>(_ type: Value.Type) {
        lock.lock()
        defer { lock.unlock() }
        factories.removeValue(forKey: ObjectIdentifier(type))
    }

    /// Returns a registered placeholder for `type`, or `nil` when none is
    /// registered. The factory is user code, so it runs after the lock is
    /// released.
    static func make<Value>(_ type: Value.Type) -> Value? {
        lock.lock()
        let factory = factories[ObjectIdentifier(type)]
        lock.unlock()
        return factory?() as? Value
    }
}

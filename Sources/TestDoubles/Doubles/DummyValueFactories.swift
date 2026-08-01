import Foundation

enum DummyValueFactories {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var factories: [
        ObjectIdentifier: @Sendable () -> Any
    ] = [:]

    static func register<Value>(
        _ type: Value.Type,
        factory: @escaping @Sendable () -> Value
    ) {
        lock.lock()
        defer { lock.unlock() }
        factories[ObjectIdentifier(type)] = factory
    }

    static func unregister<Value>(_ type: Value.Type) {
        lock.lock()
        defer { lock.unlock() }
        factories.removeValue(forKey: ObjectIdentifier(type))
    }

    static func make<Value>(_ type: Value.Type) -> Value? {
        lock.lock()
        let factory = factories[ObjectIdentifier(type)]
        lock.unlock()
        return factory?() as? Value
    }
}

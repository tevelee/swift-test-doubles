/// An event bus whose `publish` requirement is generic over the event type.
public protocol EventBus {
    func publish<Event>(_ event: Event)
}

public struct RealEventBus: EventBus {
    public init() {}
    public func publish<Event>(_ event: Event) {}
}

/// A generic equality check whose two arguments share one generic parameter.
public protocol EqualityChecker {
    func areEqual<Value>(_ lhs: Value, _ rhs: Value) -> Bool
}

public struct RealEqualityChecker: EqualityChecker {
    public init() {}
    public func areEqual<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
        false
    }
}

/// A cache whose `store` requirement is generic over both key and value.
public protocol GenericCache {
    func store<Key, Value>(_ value: Value, forKey key: Key)
}

public struct RealGenericCache: GenericCache {
    public init() {}
    public func store<Key, Value>(_ value: Value, forKey key: Key) {}
}

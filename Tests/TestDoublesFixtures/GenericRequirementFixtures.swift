/// A publish/subscribe event bus whose `publish` requirement is generic over
/// the event type — a common real-world shape, since the bus itself has no
/// reason to know about every event type in advance.
///
/// Public with a linked conformer so automatic discovery reaches the
/// requirement itself rather than failing earlier for lack of any
/// conformance, and so release-mode dead-code elimination cannot strip the
/// witness before discovery runs.
public protocol EventBus {
    func publish<Event>(_ event: Event)
}

public struct RealEventBus: EventBus {
    public init() {}
    public func publish<Event>(_ event: Event) {}
}

/// A generic equality check whose two arguments share one requirement-level
/// generic parameter — the common shape behind a type-erased "diff" or
/// "compare" utility.
public protocol EqualityChecker {
    func areEqual<Value>(_ lhs: Value, _ rhs: Value) -> Bool
}

public struct RealEqualityChecker: EqualityChecker {
    public init() {}
    public func areEqual<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
        false
    }
}

/// A type-erased cache whose `store` requirement is generic over both the key
/// and the value independently — two distinct requirement-level generic
/// parameters in one requirement.
public protocol GenericCache {
    func store<Key, Value>(_ value: Value, forKey key: Key)
}

public struct RealGenericCache: GenericCache {
    public init() {}
    public func store<Key, Value>(_ value: Value, forKey key: Key) {}
}

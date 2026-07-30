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

/// Forces both a generic value pointer and its caller-supplied metadata onto
/// the synchronous stack on every supported architecture.
public protocol GenericStackForwardingProbe {
    func measure<Value>(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int,
        value: Value
    ) -> Int
}

public struct RealGenericStackForwardingProbe:
    GenericStackForwardingProbe
{
    public init() {}

    public func measure<Value>(
        _ first: Int,
        _ second: Int,
        _ third: Int,
        _ fourth: Int,
        _ fifth: Int,
        _ sixth: Int,
        _ seventh: Int,
        _ eighth: Int,
        value: Value
    ) -> Int {
        first + second + third + fourth + fifth + sixth + seventh + eighth
            + MemoryLayout<Value>.size
    }
}

/// Generic result shapes whose concrete metadata is supplied by each caller.
public protocol GenericResultRequirementProbe {
    func echo<Value>(_ value: Value) -> Value
    func maybe<Value>(_ value: Value) -> Value?
    func make<Value>() -> Value
    func second<First, Second>(_ first: First, _ second: Second) -> Second
}

public struct RealGenericResultRequirementProbe: GenericResultRequirementProbe {
    public init() {}
    public func echo<Value>(_ value: Value) -> Value { value }
    public func maybe<Value>(_ value: Value) -> Value? { value }
    // swiftlint:disable:next unavailable_function
    public func make<Value>() -> Value {
        fatalError("The linked conformer is metadata-only.")
    }
    public func second<First, Second>(_ first: First, _ second: Second) -> Second {
        second
    }
}

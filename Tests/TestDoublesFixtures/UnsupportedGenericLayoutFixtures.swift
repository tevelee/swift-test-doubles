@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
public struct ExternalGenericPack<each Element> {
    public init() {}
}

@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
public struct ExternalConstrainedGenericPack<each Element>
where repeat each Element: ExternalFirstGenericConstraint {
    public init() {}
}

/// A requirement whose *own* generic signature uses a parameter pack. Lives
/// here, public and with a linked conformer, so automatic discovery reaches
/// the requirement itself instead of failing earlier for lack of a conformer
/// once release-mode optimization strips unreferenced private witnesses.
@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
public protocol ExternalPackRequirementProbe {
    func pack<each Argument>(_ arguments: repeat each Argument) -> Int
}

@available(
    macOS 14.0,
    iOS 17.0,
    tvOS 17.0,
    watchOS 10.0,
    visionOS 1.0,
    macCatalyst 17.0,
    *
)
public struct RealExternalPackRequirementProbe: ExternalPackRequirementProbe {
    public init() {}

    public func pack<each Argument>(_ arguments: repeat each Argument) -> Int {
        var count = 0
        for _ in repeat each arguments { count += 1 }
        return count
    }
}

/// A requirement that declares its own generic parameter (no pack). Its
/// argument's type is supplied by each caller at runtime, so automatic
/// discovery cannot describe it from the protocol alone. Public with a linked
/// conformer so discovery reaches the requirement rather than failing earlier.
public protocol ExternalGenericRequirementProbe {
    func generic<Value>(_ value: Value) -> Int
}

public struct RealExternalGenericRequirementProbe: ExternalGenericRequirementProbe {
    public init() {}

    public func generic<Value>(_ value: Value) -> Int {
        MemoryLayout<Value>.size
    }
}

public struct ExternalGenericConstraintValue:
    ExternalFirstGenericConstraint,
    ExternalSecondGenericConstraint
{
    public init() {}
}

public protocol ProtocolConstrainedGenericRequirementProbe {
    func generic<Value: ExternalFirstGenericConstraint>(_ value: Value)
}

public struct RealProtocolConstrainedGenericRequirementProbe:
    ProtocolConstrainedGenericRequirementProbe
{
    public init() {}

    public func generic<Value: ExternalFirstGenericConstraint>(_ value: Value) {}
}

public protocol MultipleConstrainedGenericRequirementProbe {
    func generic<Value: ExternalFirstGenericConstraint & ExternalSecondGenericConstraint>(
        _ value: Value
    )
}

public struct RealMultipleConstrainedGenericRequirementProbe:
    MultipleConstrainedGenericRequirementProbe
{
    public init() {}

    public func generic<Value: ExternalFirstGenericConstraint & ExternalSecondGenericConstraint>(
        _ value: Value
    ) {}
}

public final class ExternalGenericReferenceConstraintValue {
    public init() {}
}

public protocol ClassConstrainedGenericRequirementProbe {
    func generic<Value: AnyObject>(_ value: Value)
}

public struct RealClassConstrainedGenericRequirementProbe:
    ClassConstrainedGenericRequirementProbe
{
    public init() {}

    public func generic<Value: AnyObject>(_ value: Value) {}
}

public protocol NoncopyableGenericRequirementProbe {
    func generic<Value: ~Copyable>(_ value: borrowing Value)
}

public struct RealNoncopyableGenericRequirementProbe:
    NoncopyableGenericRequirementProbe
{
    public init() {}

    public func generic<Value: ~Copyable>(_ value: borrowing Value) {}
}

public protocol NonescapableGenericRequirementProbe {
    func generic<Value: ~Escapable>(_ value: borrowing Value)
}

public struct RealNonescapableGenericRequirementProbe:
    NonescapableGenericRequirementProbe
{
    public init() {}

    public func generic<Value: ~Escapable>(_ value: borrowing Value) {}
}

public protocol ConsumingGenericRequirementProbe {
    func generic<Value>(_ value: consuming Value)
}

public struct RealConsumingGenericRequirementProbe:
    ConsumingGenericRequirementProbe
{
    public init() {}

    public func generic<Value>(_ value: consuming Value) {}
}

/// A requirement-level generic parameter combined with `async`; unverified, fails closed.
public protocol AsyncGenericRequirementProbe {
    func publishAsync<Event>(_ event: Event) async
}

public struct RealAsyncGenericRequirementProbe: AsyncGenericRequirementProbe {
    public init() {}

    public func publishAsync<Event>(_ event: Event) async {}
}

/// A requirement-level generic parameter combined with typed throws; unverified, fails closed.
public protocol TypedThrowingGenericRequirementProbe {
    func publishThrows<Event>(_ event: Event) throws(ExternalReferenceFixedFailure)
}

public struct RealTypedThrowingGenericRequirementProbe: TypedThrowingGenericRequirementProbe {
    public init() {}

    public func publishThrows<Event>(_ event: Event) throws(ExternalReferenceFixedFailure) {}
}

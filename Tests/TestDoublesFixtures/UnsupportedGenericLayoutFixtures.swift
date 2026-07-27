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

/// A requirement-level generic parameter combined with `async`. The reserved
/// metadata register's interaction with async suspension is unverified
/// against the compiled ABI, so this shape fails closed.
public protocol AsyncGenericRequirementProbe {
    func publishAsync<Event>(_ event: Event) async
}

public struct RealAsyncGenericRequirementProbe: AsyncGenericRequirementProbe {
    public init() {}

    public func publishAsync<Event>(_ event: Event) async {}
}

/// A requirement-level generic parameter combined with typed throws. The
/// interaction between the reserved metadata register and typed-error
/// indirect-result transport is unverified, so this shape fails closed.
public protocol TypedThrowingGenericRequirementProbe {
    func publishThrows<Event>(_ event: Event) throws(ExternalReferenceFixedFailure)
}

public struct RealTypedThrowingGenericRequirementProbe: TypedThrowingGenericRequirementProbe {
    public init() {}

    public func publishThrows<Event>(_ event: Event) throws(ExternalReferenceFixedFailure) {}
}

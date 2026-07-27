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

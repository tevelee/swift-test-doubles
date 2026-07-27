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

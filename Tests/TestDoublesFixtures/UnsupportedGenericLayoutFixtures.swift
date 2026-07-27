@available(macOS 14.0, macCatalyst 17.0, *)
public struct ExternalGenericPack<each Element> {
    public init() {}
}

@available(macOS 14.0, macCatalyst 17.0, *)
public struct ExternalConstrainedGenericPack<each Element>
where repeat each Element: ExternalFirstGenericConstraint {
    public init() {}
}

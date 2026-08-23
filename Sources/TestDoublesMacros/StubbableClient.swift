import TestDoubles

#if TESTDOUBLES_STUBBABLE_MACROS
    /// Generates reusable test-double wiring for a closure-field client struct.
    ///
    /// Enable the `StubbableMacros` SwiftPM trait before importing this module.
    /// The generated namespace appends `Doubles` to the client name and exposes
    /// a `preset` that builds live, failing, spying, and partially overridden
    /// variants, plus a fail-closed concrete `testValue` suitable for
    /// swift-dependencies, TCA, and other environment-style dependency systems.
    /// Ordinary generic parameters and custom initializers are supported.
    /// Required non-closure stored properties become arguments of the generated
    /// `preset(...)` and `testValue(...)` factories, while initialized immutable
    /// closure properties retain their defaults.
    ///
    /// Name properties in `aliasedEndpoints` when their closure type is a
    /// global, imported, or generic type alias that syntax-only macro expansion
    /// cannot inspect:
    ///
    /// ```swift
    /// @StubbableClient(aliasedEndpoints: "load", "save")
    /// struct APIClient<Value> {
    ///     var load: ExternalLoad
    ///     var save: GenericSave<Value>
    /// }
    /// ```
    @attached(peer, names: suffixed(Doubles))
    @attached(extension, names: named(init))
    public macro StubbableClient(aliasedEndpoints: String...) =
        #externalMacro(
            module: "TestDoublesStubbableMacros",
            type: "StubbableClientMacro"
        )
#endif

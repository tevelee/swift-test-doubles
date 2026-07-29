import TestDoubles

#if TESTDOUBLES_STUBBABLE_MACROS
    /// Generates reusable test-double wiring for a closure-field client struct.
    ///
    /// Enable the `StubbableMacros` SwiftPM trait before importing this module.
    /// The generated namespace appends `Doubles` to the client name and exposes
    /// a `preset` that builds live, failing, spying, and partially overridden
    /// variants.
    @attached(peer, names: suffixed(Doubles))
    public macro StubbableClient() =
        #externalMacro(
            module: "TestDoublesStubbableMacros",
            type: "StubbableClientMacro"
        )
#endif

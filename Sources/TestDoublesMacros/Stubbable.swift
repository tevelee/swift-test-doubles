@_exported import TestDoubles

#if TESTDOUBLES_STUBBABLE_MACROS
    /// Generates a ``ManualStub`` conformer for an ordinary protocol declaration.
    ///
    /// Enable the `StubbableMacros` SwiftPM trait before importing this module.
    /// The generated type is named by appending `ManualStub` to the protocol name.
    @attached(peer, names: suffixed(ManualStub))
    public macro Stubbable() =
        #externalMacro(
            module: "TestDoublesStubbableMacros",
            type: "StubbableMacro"
        )
#endif

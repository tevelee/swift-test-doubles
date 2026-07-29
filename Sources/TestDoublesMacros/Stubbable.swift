import TestDoubles

#if TESTDOUBLES_STUBBABLE_MACROS
    /// Generates a ``ManualStub`` conformer for an ordinary protocol declaration.
    ///
    /// Enable the `StubbableMacros` SwiftPM trait before importing this module.
    /// The generated controller is named by appending `Stub` to the protocol
    /// name. Its forwarding implementation appends `StubConformer`.
    @attached(peer, names: suffixed(Stub), suffixed(StubConformer))
    public macro Stubbable() =
        #externalMacro(
            module: "TestDoublesStubbableMacros",
            type: "StubbableMacro"
        )
#endif

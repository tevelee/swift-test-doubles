extension Stub {
    /// Returns a configured runtime-generated stub value.
    ///
    /// The surrounding assignment, argument, or return context must determine the
    /// protocol existential type. Use an explicit ``Stub`` when configuration must
    /// be followed by verification.
    ///
    /// ```swift
    /// let service: any CurrencyService = Stub.make {
    ///     $0.when { $0.currency }.then { "EUR" }
    /// }
    /// ```
    ///
    /// Construction terminates the process with a diagnostic if the protocol
    /// layout or requirement signatures cannot be fabricated safely.
    ///
    /// - Parameter configure: An operation that configures the generated stub.
    /// - Returns: The configured protocol value.
    public static func make(_ configure: (Stub<P>) -> Void) -> P {
        let stub: Stub<P> = constructStubOrFail()
        configure(stub)
        return stub()
    }

    /// Asynchronously returns a configured runtime-generated stub value.
    ///
    /// The surrounding assignment, argument, or return context must determine the
    /// protocol existential type. Use this overload when configuration records an
    /// async requirement.
    ///
    /// Construction terminates the process with a diagnostic if the protocol
    /// layout or requirement signatures cannot be fabricated safely.
    ///
    /// - Parameters:
    ///   - configure: An asynchronous operation that configures the generated stub.
    ///   - isolation: The actor on which configuration runs.
    /// - Returns: The configured protocol value.
    public static func make(
        _ configure: (Stub<P>) async -> Void,
        isolation: isolated (any Actor)? = #isolation
    ) async -> P {
        let stub: Stub<P> = constructStubOrFail()
        await configure(stub)
        return stub()
    }

    private static func constructStubOrFail() -> Stub<P> {
        constructTestDoubleOrFail(.stub, for: P.self) { () throws(StubError) -> Stub<P> in
            try Stub<P>()
        }
    }
}

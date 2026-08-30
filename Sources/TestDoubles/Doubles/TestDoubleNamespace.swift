/// Namespaces supporting test-double types for autocomplete discovery.
///
/// The original global spellings remain available. These aliases group types
/// that describe observations, configuration, diagnostics, and performance.
public enum TestDouble {
    /// A whole-double interaction snapshot.
    public typealias Interactions = InteractionHistory

    /// A chronological interaction trace.
    public typealias Timeline = InteractionTimeline

    /// Construction and invocation performance measurements.
    public typealias Performance = StubPerformanceDiagnostics

    /// A structured automatic-check finding.
    public typealias Issue = TestDoubleIssue

    /// Explicit finite and terminal behavior repetition choices.
    public typealias Repetition = BehaviorRepetition

    /// A result-typed configured call handle.
    public typealias ConfiguredCall<Result> = TestDoubles.ConfiguredCall<Result>

    /// Creates a runtime-generated protocol stub controller.
    ///
    /// - Parameter protocolType: The protocol existential type to stub.
    /// - Returns: A controller for configuring and verifying the protocol.
    public static func stub<P>(
        of protocolType: P.Type
    ) throws(StubError) -> Stub<P> {
        _ = protocolType
        return try Stub<P>()
    }

    /// Creates a runtime-first stub backed by a generated compiled controller.
    ///
    /// - Parameter controllerType: The generated `CompiledStub` alias to use
    ///   when runtime construction is unavailable.
    /// - Returns: A configurable protocol stub controller.
    public static func stub<T>(
        using controllerType: CompiledStub<T>.Type
    ) -> Stub<T.StubbedProtocol> where T: AutomaticStubConformer {
        _ = controllerType
        return CompiledStub<T>.automatic()
    }

    /// Creates a compiled stub controller without attempting runtime synthesis.
    ///
    /// - Parameter controllerType: A generated or hand-written `CompiledStub`
    ///   type whose conformer forwards protocol requirements.
    /// - Returns: A compiled controller for configuring and verifying the conformer.
    public static func compiled<T>(
        _ controllerType: CompiledStub<T>.Type
    ) -> CompiledStub<T> where T: ManualStubConformer {
        _ = controllerType
        return CompiledStub<T>()
    }

    /// Creates a protocol spy controller that forwards unmatched calls.
    ///
    /// Requiring `protocolType` prevents the forwarding target's concrete type
    /// from being inferred as the type to synthesize.
    ///
    /// - Parameters:
    ///   - protocolType: The protocol existential type to spy on.
    ///   - target: The real implementation that receives unmatched calls.
    /// - Returns: A forwarding controller that also supports stubbing and verification.
    public static func spy<P>(
        of protocolType: P.Type,
        forwardingTo target: P
    ) throws(StubError) -> Spy<P> {
        _ = protocolType
        return try Spy<P>(forwardingTo: target)
    }

    /// Creates a protocol dummy controller.
    ///
    /// - Parameter protocolType: The protocol existential type to synthesize.
    /// - Returns: A controller that materializes an intentionally unusable dummy.
    public static func dummy<P>(
        of protocolType: P.Type
    ) throws(StubError) -> Dummy<P> {
        _ = protocolType
        return try Dummy<P>()
    }
}

extension Stub {
    /// The implementation route selected while constructing a stub.
    public typealias ConstructionStrategy = StubConstructionStrategy
}

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
}

extension Stub {
    /// The implementation route selected while constructing a stub.
    public typealias ConstructionStrategy = StubConstructionStrategy
}

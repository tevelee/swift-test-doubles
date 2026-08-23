/// The implementation route selected while constructing a ``Stub``.
public enum StubConstructionStrategy: Sendable {
    /// The protocol existential was synthesized at runtime.
    case runtimeGenerated

    /// A compiler-generated or hand-written `ManualStubConformer` was used.
    case compiledFallback
}

/// A runtime-generated test double for a protocol existential.
///
/// Use the throwing initializer without requirements when signatures are
/// discoverable from a linked conformer or resilient protocol descriptors.
/// Supply ``Requirement`` values when neither runtime source is available.
///
/// ```swift
/// let stub = try Stub<any Calculator>()
/// stub.when { $0.add(1, 2) }.thenReturn(42)
///
/// let calculator: any Calculator = stub()
/// ```
public class Stub<P> {
    let recorder: StubRecorder
    private let materializeValue: () -> P

    struct PreparedStub {
        let recorder: StubRecorder
        let storage: RuntimeStubFactory.Storage<P>
        let constructionPerformance: StubPerformanceDiagnostics.Construction
    }

    init(prepared: PreparedStub) {
        self.recorder = prepared.recorder
        materializeValue = { prepared.storage.materialize() }
        constructionPerformance = prepared.constructionPerformance
        constructionStrategy = .runtimeGenerated
        runtimeFallbackReason = nil
        if let session = TestDoubleTestingContext.session {
            session.register(prepared.recorder)
            let recorder = prepared.recorder
            session.registerLifetime(of: recorder) {
                recorder.hasLiveRuntimeResources
            }
        }
    }

    private init<Fallback: ManualStubConformer>(
        manualFallback: ManualStub<Fallback>,
        erasingWith erase: @escaping (Fallback) -> P,
        runtimeFallbackReason: StubError,
        constructionPerformance: StubPerformanceDiagnostics.Construction
    ) {
        recorder = manualFallback.recorder
        materializeValue = { erase(manualFallback()) }
        self.constructionPerformance = constructionPerformance
        constructionStrategy = .compiledFallback
        self.runtimeFallbackReason = runtimeFallbackReason
    }

    let constructionPerformance: StubPerformanceDiagnostics.Construction

    /// The implementation route selected for this stub.
    public let constructionStrategy: StubConstructionStrategy

    /// Why runtime construction failed before a compiled fallback was used.
    ///
    /// This is `nil` when ``constructionStrategy`` is ``StubConstructionStrategy/runtimeGenerated``.
    public let runtimeFallbackReason: StubError?

    /// Creates a stub from runtime-discovered or explicitly supplied
    /// requirement signatures.
    ///
    /// With no arguments, the stub discovers signatures from existing
    /// conformer witness tables or exported resilient-protocol requirement
    /// descriptors. Flat explicit requirements remove that dependency for a
    /// single-root protocol and must appear in protocol requirement order. Use
    /// `init(requirementsByProtocol:)` for multi-root compositions. Linked
    /// witnesses and resilient requirement symbols also validate every
    /// reliably discoverable explicit signature component.
    public convenience init(_ requirements: Requirement...) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            if requirements.isEmpty {
                try Self.prepare()
            } else {
                try Self.prepare(requirements: requirements)
            }
        }
        self.init(prepared: prepared)
    }

    /// Creates a stub that automatically falls back to a compiled conformer.
    ///
    /// Runtime synthesis is attempted first. If protocol metadata, executable
    /// memory, platform policy, or a requirement shape prevents it, the stub
    /// constructs `Fallback` through `ManualStub` and keeps the same `Stub`
    /// configuration, verification, and interaction API.
    ///
    /// Prefer the generated `YourProtocolStub.automatic()` factory when using
    /// `@Stubbable` or `ManualStubGenerator`.
    public convenience init<Fallback: ManualStubConformer>(
        fallingBackTo _: Fallback.Type,
        erasingWith erase: @escaping (Fallback) -> P
    ) {
        let constructionStartedAt = ContinuousClock.now
        do {
            let prepared = try withStubConstructionError(for: P.self) {
                try Self.prepare()
            }
            self.init(prepared: prepared)
        } catch {
            let runtimeFailedAt = ContinuousClock.now
            let fallback = ManualStub<Fallback>()
            let fallbackMaterializedAt = ContinuousClock.now
            self.init(
                manualFallback: fallback,
                erasingWith: erase,
                runtimeFallbackReason: error,
                constructionPerformance: StubPerformanceDiagnostics.Construction(
                    planPreparationDuration: constructionStartedAt.duration(
                        to: runtimeFailedAt
                    ),
                    materializationDuration: runtimeFailedAt.duration(
                        to: fallbackMaterializedAt
                    )
                )
            )
        }
    }

    /// Creates a stub using a concrete conformer's witness tables to discover
    /// its requirement signatures.
    ///
    /// Use this form for a test-only or private conformer. It reads the
    /// witness table carried by `conformer` instead of scanning the process
    /// image. The conformer is inspected during construction and is never
    /// invoked or retained by the stub.
    public convenience init(discoveringFrom conformer: P) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(discoveringFrom: conformer)
        }
        self.init(prepared: prepared)
    }

    /// Creates a stub for an unbound protocol existential using caller-supplied
    /// associated-type bindings.
    ///
    /// Supply exactly one binding for every associated type in the complete
    /// protocol layout. Requirements may use those bindings only in covariant
    /// result positions. With no explicit requirements, signatures are still
    /// discovered from a linked conformer or resilient protocol descriptors.
    public convenience init(
        associatedTypes: [AssociatedTypeBinding],
        _ requirements: Requirement...
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(
                callerAssociatedTypeBindings: associatedTypes,
                requirements: requirements
            )
        }
        self.init(prepared: prepared)
    }

    /// Creates a single-root protocol stub using automatic signature discovery
    /// plus one throwing-effect hint for each getter.
    ///
    /// Supply effects in base-first, depth-first getter declaration order;
    /// methods, initializers, and setters do not consume an entry. Every getter
    /// must have a hint because Swift runtime metadata does not distinguish a
    /// synchronous nonthrowing getter from a synchronous throwing getter. Use
    /// `init(getterEffectsByProtocol:)` to scope effects by their declaring
    /// protocol in inheritance graphs or compositions.
    public convenience init(
        getterEffects firstEffect: GetterEffect,
        _ additionalEffects: GetterEffect...
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(getterEffects: [firstEffect] + additionalEffects)
        }
        self.init(prepared: prepared)
    }

    /// Creates a stub using getter-effect hints grouped by their declaring protocols.
    ///
    /// Use this initializer for inheritance graphs and protocol compositions.
    /// Group order does not matter. Supply one group for every protocol that
    /// directly declares a getter; inherited getters belong to their original
    /// declaring protocol.
    public convenience init(
        getterEffectsByProtocol firstGroup: ProtocolGetterEffects,
        _ additionalGroups: ProtocolGetterEffects...
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(getterEffectGroups: [firstGroup] + additionalGroups)
        }
        self.init(prepared: prepared)
    }

    /// Creates a stub using explicit requirements grouped by their declaring
    /// protocols.
    ///
    /// Use this initializer for protocol compositions. Group order does not
    /// matter. Supply one group for every protocol that directly declares a
    /// callable requirement; inherited requirements belong to their original
    /// declaring protocol.
    public convenience init(
        requirementsByProtocol firstGroup: ProtocolRequirements,
        _ additionalGroups: ProtocolRequirements...
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(requirementGroups: [firstGroup] + additionalGroups)
        }
        self.init(prepared: prepared)
    }

    /// Creates a stub from an array of requirements grouped by declaring
    /// protocol. This form also supports protocols that declare no callable
    /// requirements by accepting an empty array.
    public convenience init(
        requirementsByProtocol groups: [ProtocolRequirements]
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Self.prepare(requirementGroups: groups)
        }
        self.init(prepared: prepared)
    }

    /// Resolves and caches this protocol's automatic construction plan.
    ///
    /// Call this during suite setup when the first stub should not pay for
    /// protocol layout inspection, signature discovery, and trampoline-plan
    /// preparation. Prewarming creates no recorder or generated protocol value;
    /// every later ``Stub`` still owns independent behavior and interaction
    /// state.
    ///
    /// Successful plans are shared process-wide and repeated calls are safe
    /// from concurrent tasks. Failures are not cached, so a conformance or
    /// resilient protocol image loaded later can make a subsequent call
    /// succeed.
    ///
    /// ```swift
    /// try Stub<any PaymentGateway>.prewarm()
    /// ```
    public static func prewarm() throws(StubError) {
        try withStubConstructionError(for: P.self) {
            try prewarmAutomaticPlan()
        }
    }

    /// Returns the generated protocol existential.
    public func callAsFunction() -> P {
        materializeUnchecked()
    }

    /// Assigns a name used in automatic test-double teardown diagnostics.
    ///
    /// Naming is optional, but makes a strict scope's report immediately
    /// useful when a test owns several doubles of the same protocol type.
    ///
    /// ```swift
    /// let gateway = try Stub<any PaymentGateway>().named("payment gateway")
    /// ```
    @discardableResult
    public func named(_ name: String) -> Self {
        recorder.nameTestDouble(name)
        return self
    }

    func materializeForRecording() -> P {
        materializeUnchecked()
    }

    private func materializeUnchecked() -> P {
        materializeValue()
    }

    private func withMaterializedValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let value = materializeUnchecked()
        defer { withExtendedLifetime(value) {} }
        return try operation(value)
    }

    private func withMaterializedValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        let value = materializeUnchecked()
        defer { withExtendedLifetime(value) {} }
        return try await operation(value)
    }

    /// Calls `operation` with a generated value and keeps its runtime resources alive.
    ///
    /// The operation's precise error type is preserved.
    ///
    /// Use this method when passing `type(of: value)` to code that invokes static
    /// or initializer requirements. A metatype extracted from the value must not
    /// escape `operation`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withMaterializedValue(operation)
    }

    /// Asynchronously calls `operation` with a generated value and keeps its runtime resources alive.
    ///
    /// The operation's precise error type is preserved.
    ///
    /// Use this method when passing `type(of: value)` to code that invokes static
    /// or initializer requirements. A metatype extracted from the value must not
    /// escape `operation`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withMaterializedValue(operation)
    }
}

extension Stub where P: Sendable {
    /// Returns the generated protocol existential.
    ///
    /// Same as the unconstrained `callAsFunction()`, except the compiler can
    /// verify the returned value is `Sendable`, so it may cross actor
    /// isolation boundaries without a diagnostic.
    public func callAsFunction() -> P {
        materializeUnchecked()
    }

    /// Calls `operation` with a generated value and keeps its runtime
    /// resources alive.
    ///
    /// Same as the unconstrained `withValue(_:)`, except the compiler can
    /// verify the generated value is `Sendable`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withMaterializedValue(operation)
    }

    /// Asynchronously calls `operation` with a generated value and keeps its
    /// runtime resources alive.
    ///
    /// Same as the unconstrained async `withValue(_:)`, except the compiler
    /// can verify the generated value is `Sendable`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withMaterializedValue(operation)
    }
}

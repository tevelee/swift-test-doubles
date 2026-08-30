/// Compiler-emitted evidence used to choose a safe runtime construction input.
///
/// Macros and build plugins can emit this manifest beside a generated
/// conformer. The manifest carries ordinary ``Stub/Requirement`` values, so
/// the existing runtime validator remains authoritative. It intentionally
/// exposes no direct/indirect transport switch and cannot manufacture evidence
/// for a plain unannotated protocol.
public struct StubCompilerEvidence<P>: Sendable {
    /// The runtime recipe emitted by generated source.
    public enum RuntimeConstruction: Sendable {
        /// Use linked conformers or resilient requirement symbols.
        case automaticDiscovery

        /// Use explicit requirements for one declaring protocol.
        case requirements([Stub<P>.Requirement])

        /// Use explicit requirements grouped by declaring protocol.
        case groupedRequirements([Stub<P>.ProtocolRequirements])

        /// Do not attempt runtime construction for this generated shape.
        case unavailable(reason: String)
    }

    /// The generated runtime construction recipe.
    public let runtimeConstruction: RuntimeConstruction

    /// Whether generated source also emitted a complete compiled conformer.
    public let compiledFallbackEligibility: StubCompiledEligibility

    /// Human-readable source-level eligibility for each requirement.
    public let sourceSupport: StubSourceSupportReport

    /// Creates a manifest from a safe runtime recipe and generated support report.
    public init(
        runtimeConstruction: RuntimeConstruction,
        compiledFallbackEligibility: StubCompiledEligibility,
        sourceSupport: StubSourceSupportReport
    ) {
        self.runtimeConstruction = runtimeConstruction
        self.compiledFallbackEligibility = compiledFallbackEligibility
        self.sourceSupport = sourceSupport
    }

    /// Aggregate runtime eligibility implied by the construction recipe.
    ///
    /// Automatic discovery is never reported as compiler proof. Its success is
    /// determined only when normal runtime preparation validates the protocol.
    public var runtimeEligibility: StubRuntimeEligibility {
        switch runtimeConstruction {
            case .automaticDiscovery:
                .requiresRuntimeDiscovery
            case .requirements, .groupedRequirements:
                .compilerDescribed
            case .unavailable(let reason):
                .unavailable(reason: reason)
        }
    }
}

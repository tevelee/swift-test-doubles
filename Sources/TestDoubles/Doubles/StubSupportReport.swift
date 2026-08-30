/// How source-level evidence qualifies one requirement for runtime construction.
///
/// This vocabulary deliberately avoids ABI transport choices. A requirement is
/// compiler-described only when generated source supplies its complete
/// ``Stub/Requirement`` schema. Runtime discovery remains an attempt whose
/// success is decided by normal fail-closed construction validation.
public enum StubRuntimeEligibility: Sendable, Equatable {
    /// Generated source supplied a complete requirement description.
    case compilerDescribed

    /// Construction must discover and validate the requirement at runtime.
    case requiresRuntimeDiscovery

    /// Generated source knows that runtime construction cannot support the requirement.
    case unavailable(reason: String)
}

/// How source-level evidence qualifies one requirement for compiled fallback.
public enum StubCompiledEligibility: Sendable, Equatable {
    /// A compiler-generated conformer can dispatch the requirement.
    case generatedConformer

    /// No generated conformer can dispatch the requirement.
    case unavailable(reason: String)
}

/// The source-level category of a protocol requirement.
public enum StubSourceRequirementKind: Sendable, Equatable {
    /// An ordinary instance or static method.
    case method
    /// An initializer requirement.
    case initializer
    /// A property or subscript getter.
    case getter
    /// A property or subscript setter.
    case setter
}

/// Source-level support declared for one generated protocol requirement.
///
/// This describes what a generator emitted. It does not replace runtime
/// validation and does not claim support for an unannotated protocol.
public struct StubRequirementSupport: Sendable, Equatable {
    /// The protocol that directly declares the requirement.
    public let declaringProtocol: String

    /// A human-readable source name such as `load(id:)` or `subscript`.
    public let name: String

    /// The source-level requirement category.
    public let kind: StubSourceRequirementKind

    /// The zero-based declaration order within `declaringProtocol`.
    public let declarationIndex: Int

    /// The generated runtime-construction eligibility.
    public let runtimeEligibility: StubRuntimeEligibility

    /// The generated compiled-fallback eligibility.
    public let compiledEligibility: StubCompiledEligibility

    /// Creates source-level support for one generated requirement.
    public init(
        declaringProtocol: String,
        name: String,
        kind: StubSourceRequirementKind,
        declarationIndex: Int,
        runtimeEligibility: StubRuntimeEligibility,
        compiledEligibility: StubCompiledEligibility
    ) {
        self.declaringProtocol = declaringProtocol
        self.name = name
        self.kind = kind
        self.declarationIndex = declarationIndex
        self.runtimeEligibility = runtimeEligibility
        self.compiledEligibility = compiledEligibility
    }
}

/// Source-level support emitted for a protocol by a compiler plugin or macro.
///
/// The report is declarative. Actual construction can still fail because
/// linked metadata, platform executable-memory policy, or another validated
/// runtime condition differs at the call site.
public struct StubSourceSupportReport: Sendable, Equatable {
    /// The generated protocol's source-level name.
    public let protocolName: String

    /// Requirements in stable source order.
    public let requirements: [StubRequirementSupport]

    /// Creates a source-level report in stable requirement order.
    public init(
        protocolName: String,
        requirements: [StubRequirementSupport]
    ) {
        self.protocolName = protocolName
        self.requirements = requirements
    }

    /// Whether every requirement has a compiler-described runtime recipe.
    public var runtimeIsCompilerDescribed: Bool {
        requirements.allSatisfy {
            $0.runtimeEligibility == .compilerDescribed
        }
    }

    /// Whether any requirement still depends on runtime signature discovery.
    public var needsRuntimeDiscovery: Bool {
        requirements.contains {
            $0.runtimeEligibility == .requiresRuntimeDiscovery
        }
    }

    /// Whether a generated conformer covers every requirement.
    public var hasCompleteCompiledFallback: Bool {
        requirements.allSatisfy {
            $0.compiledEligibility == .generatedConformer
        }
    }
}

/// The route actually selected for one constructed ``Stub``.
///
/// This is an observation after construction, unlike
/// ``StubSourceSupportReport``, which records generated eligibility before an
/// attempt is made.
public struct StubConstructionReport: Sendable, Equatable {
    /// The selected implementation route.
    public enum Strategy: Sendable, Equatable {
        /// The protocol existential was synthesized by the runtime.
        case runtimeGenerated
        /// A compiler-generated or hand-written conformer was selected.
        case compiledFallback
    }

    /// The runtime protocol existential that was requested.
    public let protocolName: String

    /// The implementation route selected by construction.
    public let strategy: Strategy

    /// The runtime failure preserved when compiled fallback was selected.
    public let runtimeFailureDescription: String?

}

extension Stub {
    /// A source-independent report of the route selected during construction.
    ///
    /// Runtime-generated stubs have no failure description. Compiled fallbacks
    /// preserve the same diagnostic exposed by ``runtimeFallbackReason``.
    public var constructionReport: StubConstructionReport {
        let strategy: StubConstructionReport.Strategy
        switch constructionStrategy {
            case .runtimeGenerated:
                strategy = .runtimeGenerated
            case .compiledFallback:
                strategy = .compiledFallback
        }
        return StubConstructionReport(
            protocolName: String(reflecting: P.self),
            strategy: strategy,
            runtimeFailureDescription: runtimeFallbackReason?.description
        )
    }
}

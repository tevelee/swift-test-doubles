/// A structured failure produced while constructing or using a test double.
///
/// Delivery remains the caller's responsibility: a caller may throw the
/// failure, report it through a testing framework, or stop execution. Keeping
/// delivery outside this value lets every path share one vocabulary and
/// renderer without changing its control-flow contract.
struct TestDoubleFailure: Error, Sendable, CustomStringConvertible {
    /// The lifecycle phase that could not complete.
    enum Phase: String, CaseIterable, Sendable {
        case construction
        case recording
        case configuration
        case dispatch
        case verification
    }

    /// A stable, machine-readable identifier for a failure kind.
    enum Code: String, Sendable, Hashable {
        case typeIsNotProtocol = "construction.type-is-not-protocol"
        case dummyValueNotSynthesizable = "construction.dummy-value-not-synthesizable"
        case compositionRequiresGroupedRequirements =
            "construction.composition-requires-grouped-requirements"
        case compositionRequiresGroupedGetterEffects =
            "construction.composition-requires-grouped-getter-effects"
        case invalidProtocolRequirementGroup =
            "construction.invalid-protocol-requirement-group"
        case missingProtocolRequirementGroup =
            "construction.missing-protocol-requirement-group"
        case duplicateProtocolRequirementGroup =
            "construction.duplicate-protocol-requirement-group"
        case foreignProtocolRequirementGroup =
            "construction.foreign-protocol-requirement-group"
        case invalidProtocolGetterEffectGroup =
            "construction.invalid-protocol-getter-effect-group"
        case missingProtocolGetterEffectGroup =
            "construction.missing-protocol-getter-effect-group"
        case duplicateProtocolGetterEffectGroup =
            "construction.duplicate-protocol-getter-effect-group"
        case foreignProtocolGetterEffectGroup =
            "construction.foreign-protocol-getter-effect-group"
        case getterEffectCountMismatch = "construction.getter-effect-count-mismatch"
        case unsupportedProtocolShape = "construction.unsupported-protocol-shape"
        case noConformanceFound = "construction.no-conformance-found"
        case requirementCountMismatch = "construction.requirement-count-mismatch"
        case requirementMismatch = "construction.requirement-mismatch"
        case signatureDiscoveryFailed = "construction.signature-discovery-failed"
        case trampolineAllocationFailed = "construction.trampoline-allocation-failed"
        case unsupportedTypeKind = "construction.unsupported-type-kind"
        case noRecordedRequirement = "recording.no-requirement"
        case multipleRecordedRequirements = "recording.multiple-requirements"
        case missingConfiguredRequirement = "configuration.missing-requirement"
        case requiresThrowingRequirement = "configuration.requires-throwing-requirement"
        case requiresNonnegativeDelay = "configuration.requires-nonnegative-delay"
        case requiresForwardingTarget = "configuration.requires-forwarding-target"
        case requiresExplicitCancellationValue =
            "configuration.requires-explicit-cancellation-value"
        case requiresAsyncRequirement = "configuration.requires-async-requirement"
    }

    /// Human-readable context plus structured values for tools and tests.
    struct Context: Sendable {
        struct Field: Sendable, Equatable {
            enum Key: String, Sendable {
                case actual
                case argumentCount
                case details
                case expected
                case feature
                case protocolName
                case reason
                case recordedRequirementCount
                case requiredDoubleKind
                case requirement
                case requirementIndex
                case typeDescription
                case typeName
            }

            let key: Key
            let value: String
        }

        let message: String
        let fields: [Field]
        let sourceLocation: StubSourceLocation?

        init(
            message: String,
            fields: [Field] = [],
            sourceLocation: StubSourceLocation? = nil
        ) {
            self.message = message
            self.fields = fields
            self.sourceLocation = sourceLocation
        }
    }

    /// An actionable next step and where it appears relative to the context.
    struct Recovery: Sendable, Equatable {
        enum Placement: Sendable, Equatable {
            case inline
            case nextLine
        }

        let message: String
        let placement: Placement

        static func inline(_ message: String) -> Self {
            Self(message: message, placement: .inline)
        }

        static func nextLine(_ message: String) -> Self {
            Self(message: message, placement: .nextLine)
        }
    }

    let phase: Phase
    let code: Code
    let context: Context
    let recovery: Recovery?

    init(
        phase: Phase,
        code: Code,
        context: Context,
        recovery: Recovery? = nil
    ) {
        self.phase = phase
        self.code = code
        self.context = context
        self.recovery = recovery
    }

    var description: String {
        TestDoubleFailureRenderer.render(self)
    }
}

/// The single presentation policy for structured test-double failures.
enum TestDoubleFailureRenderer {
    static func render(_ failure: TestDoubleFailure) -> String {
        guard let recovery = failure.recovery else {
            return failure.context.message
        }

        switch recovery.placement {
            case .inline:
                return failure.context.message + " " + recovery.message
            case .nextLine:
                return failure.context.message + "\n" + recovery.message
        }
    }
}

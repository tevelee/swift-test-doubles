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
    struct Code: RawRepresentable, Sendable, Hashable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(_ rawValue: String) {
            self.init(rawValue: rawValue)
        }

        static let typeIsNotProtocol = Self("construction.type-is-not-protocol")
        static let dummyValueNotSynthesizable = Self(
            "construction.dummy-value-not-synthesizable"
        )
        static let compositionRequiresGroupedRequirements = Self(
            "construction.composition-requires-grouped-requirements"
        )
        static let compositionRequiresGroupedGetterEffects = Self(
            "construction.composition-requires-grouped-getter-effects"
        )
        static let invalidProtocolRequirementGroup = Self(
            "construction.invalid-protocol-requirement-group"
        )
        static let missingProtocolRequirementGroup = Self(
            "construction.missing-protocol-requirement-group"
        )
        static let duplicateProtocolRequirementGroup = Self(
            "construction.duplicate-protocol-requirement-group"
        )
        static let foreignProtocolRequirementGroup = Self(
            "construction.foreign-protocol-requirement-group"
        )
        static let invalidProtocolGetterEffectGroup = Self(
            "construction.invalid-protocol-getter-effect-group"
        )
        static let missingProtocolGetterEffectGroup = Self(
            "construction.missing-protocol-getter-effect-group"
        )
        static let duplicateProtocolGetterEffectGroup = Self(
            "construction.duplicate-protocol-getter-effect-group"
        )
        static let foreignProtocolGetterEffectGroup = Self(
            "construction.foreign-protocol-getter-effect-group"
        )
        static let getterEffectCountMismatch = Self(
            "construction.getter-effect-count-mismatch"
        )
        static let unsupportedProtocolShape = Self("construction.unsupported-protocol-shape")
        static let noConformanceFound = Self("construction.no-conformance-found")
        static let requirementCountMismatch = Self("construction.requirement-count-mismatch")
        static let requirementMismatch = Self("construction.requirement-mismatch")
        static let signatureDiscoveryFailed = Self("construction.signature-discovery-failed")
        static let trampolineAllocationFailed = Self(
            "construction.trampoline-allocation-failed"
        )
        static let unsupportedTypeKind = Self("construction.unsupported-type-kind")

        // Initial vocabulary for later recording, configuration, dispatch,
        // and verification adapters. More specific codes can be added as
        // those paths migrate without changing the failure interface.
        static let recordingFailed = Self("recording.failed")
        static let invalidConfiguration = Self("configuration.invalid")
        static let dispatchFailed = Self("dispatch.failed")
        static let verificationFailed = Self("verification.failed")
    }

    /// Human-readable context plus structured values for tools and tests.
    struct Context: Sendable {
        struct Field: Sendable, Equatable {
            let key: String
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

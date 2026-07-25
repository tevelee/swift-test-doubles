import TestDoublesRuntime
/// Errors reported while constructing a runtime-generated test double.
public enum StubError: Error, Sendable, CustomStringConvertible {
    private static let manualStubbingRecovery =
        "Recovery: Use `ManualStub` with a hand-written `StubConformer`, or write a "
        + "hand-written fake, when this protocol must be stubbed."

    /// The generic argument is not a protocol existential.
    case typeIsNotProtocol(typeDescription: String)

    /// Flat explicit requirements were supplied for a multi-root composition.
    case compositionRequiresGroupedRequirements(typeDescription: String)

    /// Flat getter-effect hints were supplied for a multi-root composition.
    case compositionRequiresGroupedGetterEffects(typeDescription: String)

    /// A grouped requirement key does not identify exactly one protocol.
    case invalidProtocolRequirementGroup(typeDescription: String)

    /// A directly declaring protocol has no explicit requirement group.
    case missingProtocolRequirementGroup(protocolName: String)

    /// A directly declaring protocol has more than one explicit group.
    case duplicateProtocolRequirementGroup(protocolName: String)

    /// A grouped protocol does not directly declare requirements in the stubbed existential.
    case foreignProtocolRequirementGroup(protocolName: String, typeDescription: String)

    /// A grouped getter-effect key does not identify exactly one protocol.
    case invalidProtocolGetterEffectGroup(typeDescription: String)

    /// A directly declaring protocol has no getter-effect group.
    case missingProtocolGetterEffectGroup(protocolName: String)

    /// A directly declaring protocol has more than one getter-effect group.
    case duplicateProtocolGetterEffectGroup(protocolName: String)

    /// A grouped protocol does not directly declare getters in the stubbed existential.
    case foreignProtocolGetterEffectGroup(protocolName: String, typeDescription: String)

    /// Getter-effect hints do not cover every getter declared by one protocol.
    case getterEffectCountMismatch(protocolName: String, expected: Int, actual: Int)

    /// The protocol uses a runtime shape that the trampoline cannot represent.
    case unsupportedProtocolShape(protocolName: String, reason: String)

    /// No concrete conformance is linked for automatic signature discovery.
    case noConformanceFound(protocolName: String)

    /// Explicit requirements do not cover every supported protocol entry.
    case requirementCountMismatch(protocolName: String, expected: Int, actual: Int)

    /// An explicit requirement differs in kind or in a discoverable part of
    /// its linked signature at a zero-based protocol index.
    case requirementMismatch(
        protocolName: String,
        requirementIndex: Int,
        expected: String,
        actual: String
    )

    /// Automatic signature discovery failed at a zero-based requirement index.
    case signatureDiscoveryFailed(
        protocolName: String,
        requirementIndex: Int,
        details: String
    )

    /// Executable trampoline allocation failed at a zero-based requirement index.
    case trampolineAllocationFailed(requirementIndex: Int)

    /// Runtime metadata has a type kind the trampoline cannot represent.
    case unsupportedTypeKind(typeName: String)

    /// An actionable description of the construction failure.
    public var description: String {
        switch self {
            case .typeIsNotProtocol(let typeDescription):
                return "Could not extract a protocol from '\(typeDescription)'. Use a protocol existential such as `any YourProtocol` as the generic argument."

            case .compositionRequiresGroupedRequirements(let typeDescription):
                return "Protocol composition '\(typeDescription)' requires grouped explicit requirements. Use `init(requirementsByProtocol:)` with one `ProtocolRequirements.requirements(declaredBy:_:)` group per declaring protocol."

            case .compositionRequiresGroupedGetterEffects(let typeDescription):
                return "Protocol composition '\(typeDescription)' requires grouped getter effects. Use `init(getterEffectsByProtocol:)` with one `ProtocolGetterEffects.effects(declaredBy:_:)` group per protocol that declares getters."

            case .invalidProtocolRequirementGroup(let typeDescription):
                return "'\(typeDescription)' does not identify one protocol. Each explicit requirement group must use `YourProtocol.self`."

            case .missingProtocolRequirementGroup(let protocolName):
                return "Missing explicit requirements for protocol '\(protocolName)'. Supply exactly one group for every protocol that directly declares callable requirements."

            case .duplicateProtocolRequirementGroup(let protocolName):
                return "Explicit requirements for protocol '\(protocolName)' were supplied more than once. Combine them into one group."

            case .foreignProtocolRequirementGroup(let protocolName, let typeDescription):
                return "Protocol '\(protocolName)' does not directly declare callable requirements in '\(typeDescription)'. Remove that explicit requirement group."

            case .invalidProtocolGetterEffectGroup(let typeDescription):
                return "'\(typeDescription)' does not identify one protocol. Each getter-effect group must use `YourProtocol.self`."

            case .missingProtocolGetterEffectGroup(let protocolName):
                return "Missing getter effects for protocol '\(protocolName)'. Supply exactly one group for every protocol that directly declares getters."

            case .duplicateProtocolGetterEffectGroup(let protocolName):
                return "Getter effects for protocol '\(protocolName)' were supplied more than once. Combine them into one group."

            case .foreignProtocolGetterEffectGroup(let protocolName, let typeDescription):
                return "Protocol '\(protocolName)' does not directly declare getters in '\(typeDescription)'. Remove that getter-effect group."

            case .getterEffectCountMismatch(let protocolName, let expected, let actual):
                return "Expected \(expected) getter effects for '\(protocolName)', but received \(actual). Supply one effect for every getter in declaration order."

            case .unsupportedProtocolShape(let protocolName, let reason):
                return "Protocol '\(protocolName)' is not supported. \(reason)\n\(Self.manualStubbingRecovery)"

            case .noConformanceFound(let protocolName):
                return "Automatic discovery found neither a linked conformer nor resilient requirement symbols for '\(protocolName)'.\n"
                    + "Choose a construction path:\n"
                    + "1. Linked conformer: Link and reference a concrete conforming instance as a protocol existential, then use `try Stub<any P>()`. TestDoubles inspects it; it does not invoke it.\n"
                    + "2. Library evolution: Build the protocol module with library evolution so it exports resilient requirement symbols, then use `try Stub<any P>()`; no conformer is needed.\n"
                    + "3. Neither source available: Prefer `Requirement` factories using "
                    + "`signatureOf:` protocol members. Use source-less factories "
                    + "only when the reference forms cannot express the ABI shape, and match "
                    + "the declaration exactly. Group requirements by declaring protocol for "
                    + "compositions."

            case .requirementCountMismatch(let protocolName, let expected, let actual):
                return "Expected \(expected) requirements for '\(protocolName)', but received \(actual). Supply every mockable requirement in declaration order."

            case .requirementMismatch(let protocolName, let requirementIndex, let expected, let actual):
                return "Requirement \(requirementIndex) for '\(protocolName)' is `\(expected)`, but the supplied `Stub.Requirement` describes `\(actual)`. Update that requirement to match the protocol declaration."

            case .signatureDiscoveryFailed(let protocolName, let requirementIndex, let details):
                return "Could not discover the signature of '\(protocolName)' requirement \(requirementIndex). \(details)\n"
                    + "Recovery: Prefer a `Stub.Requirement` using `signatureOf:` when it "
                    + "supports the declaration. Use a source-less factory only when "
                    + "necessary and match the ABI shape exactly. Otherwise use `ManualStub` "
                    + "with a hand-written `StubConformer`."

            case .trampolineAllocationFailed(let requirementIndex):
                return "Could not allocate an executable trampoline for requirement \(requirementIndex).\n"
                    + Self.manualStubbingRecovery

            case .unsupportedTypeKind(let typeName):
                return "Stub does not support the runtime type kind used by '\(typeName)'.\n"
                    + Self.manualStubbingRecovery
        }
    }
}

extension StubError {
    /// Converts a package-only runtime construction failure into the stable
    /// public error vocabulary without changing its diagnostic payload.
    init(_ runtimeError: RuntimeConstructionError) {
        switch runtimeError {
            case .typeIsNotProtocol(let typeDescription):
                self = .typeIsNotProtocol(typeDescription: typeDescription)
            case .unsupportedTypeKind(let typeName):
                self = .unsupportedTypeKind(typeName: typeName)
            case .unsupportedProtocolShape(let protocolName, let reason):
                self = .unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: reason
                )
            case .noConformanceFound(let protocolName):
                self = .noConformanceFound(protocolName: protocolName)
            case .signatureDiscoveryFailed(
                let protocolName,
                let requirementIndex,
                let details
            ):
                self = .signatureDiscoveryFailed(
                    protocolName: protocolName,
                    requirementIndex: requirementIndex,
                    details: details
                )
            case .requirementCountMismatch(
                let protocolName,
                let expected,
                let actual
            ):
                self = .requirementCountMismatch(
                    protocolName: protocolName,
                    expected: expected,
                    actual: actual
                )
            case .requirementMismatch(
                let protocolName,
                let requirementIndex,
                let expected,
                let actual
            ):
                self = .requirementMismatch(
                    protocolName: protocolName,
                    requirementIndex: requirementIndex,
                    expected: expected,
                    actual: actual
                )
            case .forwardingUnsupported(let protocolName, let reason):
                self = .unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: Self.forwardingDiagnostic(reason)
                )
            case .trampolineAllocationFailed(let requirementIndex):
                self = .trampolineAllocationFailed(
                    requirementIndex: requirementIndex
                )
        }
    }

    private static func forwardingDiagnostic(
        _ reason: RuntimeForwardingUnsupportedReason
    ) -> String {
        switch reason {
            case .pairedLegacyReadAndYieldingBorrow:
                return "Forwarding Spy does not yet support Swift 6.4's paired legacy read and yielding-borrow witnesses. Use a Stub or a hand-written spy."
            case .nonInstanceRequirement(let index):
                return "Forwarding Spy supports instance requirements only; requirement \(index) uses a metatype receiver."
            case .simd(let index):
                return "Forwarding Spy does not yet support SIMD arguments or results in requirement \(index)."
            case .functionValues(let index):
                return "Forwarding Spy does not yet support function-valued arguments or results in requirement \(index)."
            case .outgoingStackWords(let index, let limit):
                return "Forwarding Spy requirement \(index) needs more outgoing stack transport than \(limit) words support. Use fewer arguments or a hand-written spy."
            case .dynamicSelfResult(let index):
                return "Forwarding Spy does not yet support dynamic Self results in requirement \(index)."
            case .selfArguments(let index):
                return "Forwarding Spy does not support direct or Optional Self arguments in requirement \(index). Use an automatic Stub or a hand-written spy."
            case .hiddenArguments(let index):
                return "Forwarding Spy requirement \(index) uses stack arguments or leaves no registers for its target metadata and witness table. Use fewer arguments or a hand-written spy."
        }
    }
}

import Testing
import TestDoubles

@Suite struct StubErrorTests {
    @Test(arguments: stubErrorDescriptions)
    func descriptionsAreActionable(error: StubError, expected: String) {
        #expect(error.description == expected)
    }
}

private let stubErrorDescriptions: [(StubError, String)] = [
    (
        .typeIsNotProtocol(typeDescription: "Int"),
        "Could not extract a protocol from 'Int'. Use a protocol existential such as `any YourProtocol` as the generic argument."
    ),
    (
        .compositionRequiresGroupedRequirements(typeDescription: "First & Second"),
        "Protocol composition 'First & Second' requires grouped explicit requirements. Use `init(requirementsByProtocol:)` with one `ProtocolRequirements.requirements(declaredBy:_:)` group per declaring protocol."
    ),
    (
        .compositionRequiresGroupedGetterEffects(typeDescription: "First & Second"),
        "Protocol composition 'First & Second' requires grouped getter effects. Use `init(getterEffectsByProtocol:)` with one `ProtocolGetterEffects.effects(declaredBy:_:)` group per protocol that declares getters."
    ),
    (
        .invalidProtocolRequirementGroup(typeDescription: "Swift.Int"),
        "'Swift.Int' does not identify one protocol. Each explicit requirement group must use `YourProtocol.self`."
    ),
    (
        .missingProtocolRequirementGroup(protocolName: "First"),
        "Missing explicit requirements for protocol 'First'. Supply exactly one group for every protocol that directly declares callable requirements."
    ),
    (
        .duplicateProtocolRequirementGroup(protocolName: "First"),
        "Explicit requirements for protocol 'First' were supplied more than once. Combine them into one group."
    ),
    (
        .foreignProtocolRequirementGroup(
            protocolName: "Other",
            typeDescription: "First & Second"
        ),
        "Protocol 'Other' does not directly declare callable requirements in 'First & Second'. Remove that explicit requirement group."
    ),
    (
        .invalidProtocolGetterEffectGroup(typeDescription: "Swift.Int"),
        "'Swift.Int' does not identify one protocol. Each getter-effect group must use `YourProtocol.self`."
    ),
    (
        .missingProtocolGetterEffectGroup(protocolName: "First"),
        "Missing getter effects for protocol 'First'. Supply exactly one group for every protocol that directly declares getters."
    ),
    (
        .duplicateProtocolGetterEffectGroup(protocolName: "First"),
        "Getter effects for protocol 'First' were supplied more than once. Combine them into one group."
    ),
    (
        .foreignProtocolGetterEffectGroup(
            protocolName: "Other",
            typeDescription: "First & Second"
        ),
        "Protocol 'Other' does not directly declare getters in 'First & Second'. Remove that getter-effect group."
    ),
    (
        .getterEffectCountMismatch(protocolName: "First", expected: 2, actual: 1),
        "Expected 2 getter effects for 'First', but received 1. Supply one effect for every getter in declaration order."
    ),
    (
        .unsupportedProtocolShape(protocolName: "Service", reason: "The requirement shape is unsupported."),
        "Protocol 'Service' is not supported. The requirement shape is unsupported.\n"
            + manualStubbingRecovery
    ),
    (
        .noConformanceFound(protocolName: "Service"),
        "Automatic discovery found neither a linked conformer nor resilient requirement symbols for 'Service'.\n"
            + "Choose a construction path:\n"
            + "1. Linked conformer: Link and reference a concrete conforming instance as a protocol existential, then use `try Stub<any P>()`. TestDoubles inspects it; it does not invoke it.\n"
            + "2. Library evolution: Build the protocol module with library evolution so it exports resilient requirement symbols, then use `try Stub<any P>()`; no conformer is needed.\n"
            + "3. Neither source available: Pass explicit `Stub.Requirement` values to `Stub<any P>(...)`, grouped by declaring protocol for compositions."
    ),
    (
        .requirementCountMismatch(protocolName: "Service", expected: 2, actual: 1),
        "Expected 2 requirements for 'Service', but received 1. Supply every mockable requirement in declaration order."
    ),
    (
        .requirementMismatch(
            protocolName: "Service",
            requirementIndex: 1,
            expected: "method",
            actual: "getter"
        ),
        "Requirement 1 for 'Service' is `method`, but the supplied `Stub.Requirement` describes `getter`. Update that requirement to match the protocol declaration."
    ),
    (
        .signatureDiscoveryFailed(
            protocolName: "Service",
            requirementIndex: 2,
            details: "No replacement was observed."
        ),
        "Could not discover the signature of 'Service' requirement 2. No replacement was observed.\n"
            + "Recovery: Supply explicit `Stub.Requirement` values when the signature is supported. Otherwise use `ManualStub` with a hand-written `StubConformer`."
    ),
    (
        .trampolineAllocationFailed(requirementIndex: 3),
        "Could not allocate an executable trampoline for requirement 3.\n"
            + manualStubbingRecovery
    ),
    (
        .unsupportedTypeKind(typeName: "Service.Type"),
        "Stub does not support the runtime type kind used by 'Service.Type'.\n"
            + manualStubbingRecovery
    )
]

private let manualStubbingRecovery =
    "Recovery: Use `ManualStub` with a hand-written `StubConformer`, or write a "
    + "hand-written fake, when this protocol must be stubbed."

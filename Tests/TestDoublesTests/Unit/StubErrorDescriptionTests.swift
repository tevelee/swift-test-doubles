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
        .dummyValueNotSynthesizable(typeDescription: "Example.Reference"),
        "Could not safely synthesize a dummy value for 'Example.Reference'. Use `Dummy.make(using:)` or `Dummy.init(using:)` to supply a valid placeholder."
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
            + "3. Neither source available: Prefer `Requirement` factories using "
            + "`signatureOf:` protocol members. Use source-less factories "
            + "only when the reference forms cannot express the ABI shape, and match "
            + "the declaration exactly. Group requirements by declaring protocol for "
            + "compositions."
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
            + "Recovery: Prefer a `Stub.Requirement` using `signatureOf:` when it "
            + "supports the declaration. Use a source-less factory only when "
            + "necessary and match the ABI shape exactly. Otherwise use `ManualStub` "
            + "with a hand-written `ManualStubConformer`."
    ),
    (
        .trampolineAllocationFailed(requirementIndex: 3),
        "Could not allocate an executable trampoline for requirement 3. "
            + "The process could not map executable memory, so no witness table was "
            + "published. Requirement 3 is the first witness slot the runtime reached, "
            + "not a requirement it rejects; every protocol reports the slot it happened "
            + "to start with.\n"
            + executableMemoryRecovery
    ),
    (
        .unsupportedTypeKind(typeName: "Service.Type"),
        "Stub does not support the runtime type kind used by 'Service.Type'.\n"
            + manualStubbingRecovery
    )
]

private let manualStubbingRecovery =
    "Recovery: Use `ManualStub` with a hand-written `ManualStubConformer`, or write a "
    + "hand-written fake, when this protocol must be stubbed."

// Mirrors the branch `StubError` reports on the platform under test.
private let executableMemoryRecovery: String = {
    #if os(WASI)
        return "WebAssembly has no facility for executable memory, so the runtime "
            + "trampoline cannot run under WASI at all. No configuration changes that.\n"
            + manualStubbingRecovery
    #elseif os(macOS) || targetEnvironment(macCatalyst)
        return "A macOS process signed with the hardened runtime may only map JIT "
            + "memory when it carries the `com.apple.security.cs.allow-jit` "
            + "entitlement, and a `.xctest` bundle inherits that from the process it "
            + "is loaded into. This usually means an app test target running on My "
            + "Mac whose host app enables the hardened runtime.\n"
            + "Pick one:\n"
            + "1. Grant the entitlement on the host app target, not on the test "
            + "bundle: Signing & Capabilities, add Hardened Runtime, check \"Allow "
            + "Execution of JIT-compiled Code\" (`RUNTIME_EXCEPTION_ALLOW_JIT = YES`).\n"
            + "2. Turn off `ENABLE_HARDENED_RUNTIME` for the configuration the tests "
            + "run in.\n"
            + "3. Run the same tests on a simulator destination, or from the command "
            + "line with `swift test`, where the hardened runtime does not apply.\n"
            + "Confirm option 1 without editing the project: `xcodebuild test -scheme "
            + "YourScheme -destination 'platform=macOS' RUNTIME_EXCEPTION_ALLOW_JIT=YES`.\n"
            + manualStubbingRecovery
    #elseif (os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && !targetEnvironment(simulator)
        return "Physical Apple devices never let a process map executable memory. "
            + "That is a platform policy, not a project setting, so no entitlement "
            + "enables it. Run runtime-generated doubles on a simulator destination "
            + "or on macOS instead.\n"
            + manualStubbingRecovery
    #else
        return "This platform usually permits executable mappings, so look for a "
            + "policy or a limit that blocked this one: a kernel, container, or "
            + "sandbox rule that forbids mapping writable memory executable, an "
            + "exhausted address space, or a process memory limit.\n"
            + manualStubbingRecovery
    #endif
}()

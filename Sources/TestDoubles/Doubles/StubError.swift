/// Errors reported while constructing a runtime-generated test double.
public enum StubError: Error, Sendable, Equatable, CustomStringConvertible {
    private static let manualStubbingRecovery =
        "Recovery: Use `CompiledStub` with a hand-written `ManualStubConformer`, or write a "
        + "hand-written fake, when this protocol must be stubbed."

    /// Reports only the recovery that applies on the platform under test.
    private static var executableMemoryRecovery: String {
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
    }

    /// The generic argument is not a protocol existential.
    case typeIsNotProtocol(typeDescription: String)

    /// A concrete dummy value cannot be initialized safely without a factory.
    case dummyValueNotSynthesizable(typeDescription: String)

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
    ///
    /// The index names the first witness slot attempted, not a rejected
    /// requirement. See <doc:ConstructionGuide> for the hardened-runtime case.
    case trampolineAllocationFailed(requirementIndex: Int)

    /// Runtime metadata has a type kind the trampoline cannot represent.
    case unsupportedTypeKind(typeName: String)

    var testDoubleFailure: TestDoubleFailure {
        switch self {
            case .typeIsNotProtocol(let typeDescription):
                return Self.constructionFailure(
                    code: .typeIsNotProtocol,
                    message: "Could not extract a protocol from '\(typeDescription)'.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline(
                        "Use a protocol existential such as `any YourProtocol` as the generic argument."
                    )
                )

            case .dummyValueNotSynthesizable(let typeDescription):
                return Self.constructionFailure(
                    code: .dummyValueNotSynthesizable,
                    message: "Could not safely synthesize a dummy value for '\(typeDescription)'.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline(
                        "Use `Dummy.make(using:)` or `Dummy.init(using:)` to supply a valid placeholder."
                    )
                )

            case .compositionRequiresGroupedRequirements(let typeDescription):
                return Self.constructionFailure(
                    code: .compositionRequiresGroupedRequirements,
                    message: "Protocol composition '\(typeDescription)' requires grouped explicit requirements.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline(
                        "Use `init(requirementsByProtocol:)` with one `ProtocolRequirements.requirements(declaredBy:_:)` group per declaring protocol."
                    )
                )

            case .compositionRequiresGroupedGetterEffects(let typeDescription):
                return Self.constructionFailure(
                    code: .compositionRequiresGroupedGetterEffects,
                    message: "Protocol composition '\(typeDescription)' requires grouped getter effects.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline(
                        "Use `init(getterEffectsByProtocol:)` with one `ProtocolGetterEffects.effects(declaredBy:_:)` group per protocol that declares getters."
                    )
                )

            case .invalidProtocolRequirementGroup(let typeDescription):
                return Self.constructionFailure(
                    code: .invalidProtocolRequirementGroup,
                    message: "'\(typeDescription)' does not identify one protocol.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline(
                        "Each explicit requirement group must use `YourProtocol.self`."
                    )
                )

            case .missingProtocolRequirementGroup(let protocolName):
                return Self.constructionFailure(
                    code: .missingProtocolRequirementGroup,
                    message: "Missing explicit requirements for protocol '\(protocolName)'.",
                    fields: [.init(key: .protocolName, value: protocolName)],
                    recovery: .inline(
                        "Supply exactly one group for every protocol that directly declares callable requirements."
                    )
                )

            case .duplicateProtocolRequirementGroup(let protocolName):
                return Self.constructionFailure(
                    code: .duplicateProtocolRequirementGroup,
                    message: "Explicit requirements for protocol '\(protocolName)' were supplied more than once.",
                    fields: [.init(key: .protocolName, value: protocolName)],
                    recovery: .inline("Combine them into one group.")
                )

            case .foreignProtocolRequirementGroup(let protocolName, let typeDescription):
                return Self.constructionFailure(
                    code: .foreignProtocolRequirementGroup,
                    message: "Protocol '\(protocolName)' does not directly declare callable requirements in '\(typeDescription)'.",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .typeDescription, value: typeDescription)
                    ],
                    recovery: .inline("Remove that explicit requirement group.")
                )

            case .invalidProtocolGetterEffectGroup(let typeDescription):
                return Self.constructionFailure(
                    code: .invalidProtocolGetterEffectGroup,
                    message: "'\(typeDescription)' does not identify one protocol.",
                    fields: [.init(key: .typeDescription, value: typeDescription)],
                    recovery: .inline("Each getter-effect group must use `YourProtocol.self`.")
                )

            case .missingProtocolGetterEffectGroup(let protocolName):
                return Self.constructionFailure(
                    code: .missingProtocolGetterEffectGroup,
                    message: "Missing getter effects for protocol '\(protocolName)'.",
                    fields: [.init(key: .protocolName, value: protocolName)],
                    recovery: .inline(
                        "Supply exactly one group for every protocol that directly declares getters."
                    )
                )

            case .duplicateProtocolGetterEffectGroup(let protocolName):
                return Self.constructionFailure(
                    code: .duplicateProtocolGetterEffectGroup,
                    message: "Getter effects for protocol '\(protocolName)' were supplied more than once.",
                    fields: [.init(key: .protocolName, value: protocolName)],
                    recovery: .inline("Combine them into one group.")
                )

            case .foreignProtocolGetterEffectGroup(let protocolName, let typeDescription):
                return Self.constructionFailure(
                    code: .foreignProtocolGetterEffectGroup,
                    message: "Protocol '\(protocolName)' does not directly declare getters in '\(typeDescription)'.",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .typeDescription, value: typeDescription)
                    ],
                    recovery: .inline("Remove that getter-effect group.")
                )

            case .getterEffectCountMismatch(let protocolName, let expected, let actual):
                return Self.constructionFailure(
                    code: .getterEffectCountMismatch,
                    message: "Expected \(expected) getter effects for '\(protocolName)', but received \(actual).",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .expected, value: String(expected)),
                        .init(key: .actual, value: String(actual))
                    ],
                    recovery: .inline("Supply one effect for every getter in declaration order.")
                )

            case .unsupportedProtocolShape(let protocolName, let reason):
                return Self.constructionFailure(
                    code: .unsupportedProtocolShape,
                    message: "Protocol '\(protocolName)' is not supported. \(reason)",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .reason, value: reason)
                    ],
                    recovery: .nextLine(Self.manualStubbingRecovery)
                )

            case .noConformanceFound(let protocolName):
                return Self.constructionFailure(
                    code: .noConformanceFound,
                    message: "Automatic discovery found neither a linked conformer nor resilient requirement symbols for '\(protocolName)'.",
                    fields: [.init(key: .protocolName, value: protocolName)],
                    recovery: .nextLine(
                        "Choose a construction path:\n"
                            + "1. Linked conformer: Link and reference a concrete conforming instance as a protocol existential, then use `try Stub<any P>()`. TestDoubles inspects it; it does not invoke it.\n"
                            + "2. Library evolution: Build the protocol module with library evolution so it exports resilient requirement symbols, then use `try Stub<any P>()`; no conformer is needed.\n"
                            + "3. Neither source available: Prefer `Requirement` factories using "
                            + "`signatureOf:` protocol members. Use source-less factories "
                            + "only when the reference forms cannot express the ABI shape, and match "
                            + "the declaration exactly. Group requirements by declaring protocol for "
                            + "compositions."
                    )
                )

            case .requirementCountMismatch(let protocolName, let expected, let actual):
                return Self.constructionFailure(
                    code: .requirementCountMismatch,
                    message: "Expected \(expected) requirements for '\(protocolName)', but received \(actual).",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .expected, value: String(expected)),
                        .init(key: .actual, value: String(actual))
                    ],
                    recovery: .inline(
                        "Supply every mockable requirement in declaration order."
                    )
                )

            case .requirementMismatch(
                let protocolName,
                let requirementIndex,
                let expected,
                let actual
            ):
                return Self.constructionFailure(
                    code: .requirementMismatch,
                    message: "Requirement \(requirementIndex) for '\(protocolName)' is `\(expected)`, but the supplied `Stub.Requirement` describes `\(actual)`.",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .requirementIndex, value: String(requirementIndex)),
                        .init(key: .expected, value: expected),
                        .init(key: .actual, value: actual)
                    ],
                    recovery: .inline(
                        "Update that requirement to match the protocol declaration."
                    )
                )

            case .signatureDiscoveryFailed(let protocolName, let requirementIndex, let details):
                return Self.constructionFailure(
                    code: .signatureDiscoveryFailed,
                    message: "Could not discover the signature of '\(protocolName)' requirement \(requirementIndex). \(details)",
                    fields: [
                        .init(key: .protocolName, value: protocolName),
                        .init(key: .requirementIndex, value: String(requirementIndex)),
                        .init(key: .details, value: details)
                    ],
                    recovery: .nextLine(
                        "Recovery: Prefer a `Stub.Requirement` using `signatureOf:` when it "
                            + "supports the declaration. Use a source-less factory only when "
                            + "necessary and match the ABI shape exactly. Otherwise use `CompiledStub` "
                            + "with a hand-written `ManualStubConformer`."
                    )
                )

            case .trampolineAllocationFailed(let requirementIndex):
                return Self.constructionFailure(
                    code: .trampolineAllocationFailed,
                    message: "Could not allocate an executable trampoline for requirement \(requirementIndex). "
                        + "The process could not map executable memory, so no witness table was "
                        + "published. Requirement \(requirementIndex) is the first witness slot the "
                        + "runtime reached, not a requirement it rejects; every protocol reports the "
                        + "slot it happened to start with.",
                    fields: [
                        .init(key: .requirementIndex, value: String(requirementIndex))
                    ],
                    recovery: .nextLine(Self.executableMemoryRecovery)
                )

            case .unsupportedTypeKind(let typeName):
                return Self.constructionFailure(
                    code: .unsupportedTypeKind,
                    message: "Stub does not support the runtime type kind used by '\(typeName)'.",
                    fields: [.init(key: .typeName, value: typeName)],
                    recovery: .nextLine(Self.manualStubbingRecovery)
                )
        }
    }

    /// An actionable description of the construction failure.
    public var description: String {
        testDoubleFailure.description
    }

    private static func constructionFailure(
        code: TestDoubleFailure.Code,
        message: String,
        fields: [TestDoubleFailure.Context.Field],
        recovery: TestDoubleFailure.Recovery
    ) -> TestDoubleFailure {
        TestDoubleFailure(
            phase: .construction,
            code: code,
            context: .init(message: message, fields: fields),
            recovery: recovery
        )
    }
}

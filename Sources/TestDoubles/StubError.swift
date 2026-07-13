/// Errors reported while constructing a ``Stub``.
public enum StubError: Error, Sendable, CustomStringConvertible {
    /// The generic argument is not a protocol existential.
    case typeIsNotProtocol(typeDescription: String)

    /// The generic argument contains more than one protocol.
    case unsupportedProtocolComposition(typeDescription: String)

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
            return "Could not extract a protocol from '\(typeDescription)'. Use `Stub<any YourProtocol>`."

        case .unsupportedProtocolComposition(let typeDescription):
            return "Protocol compositions such as '\(typeDescription)' are not supported. Stub one protocol at a time."

        case .unsupportedProtocolShape(let protocolName, let reason):
            return "Protocol '\(protocolName)' is not supported. \(reason)"

        case .noConformanceFound(let protocolName):
            return "No conformer for '\(protocolName)' is linked into this process. Supply explicit `Stub.Requirement` values."

        case .requirementCountMismatch(let protocolName, let expected, let actual):
            return "Expected \(expected) requirements for '\(protocolName)', but received \(actual). Supply every mockable requirement in declaration order."

        case .requirementMismatch(let protocolName, let requirementIndex, let expected, let actual):
            return "Requirement \(requirementIndex) for '\(protocolName)' is `\(expected)`, but the supplied `Stub.Requirement` describes `\(actual)`."

        case .signatureDiscoveryFailed(let protocolName, let requirementIndex, let details):
            return "Could not discover the signature of '\(protocolName)' requirement \(requirementIndex). \(details)"

        case .trampolineAllocationFailed(let requirementIndex):
            return "Could not allocate an executable trampoline for requirement \(requirementIndex)."

        case .unsupportedTypeKind(let typeName):
            return "Stub does not support the runtime type kind used by '\(typeName)'."
        }
    }
}

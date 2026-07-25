/// Failures reported while constructing a runtime-generated conformance.
///
/// This vocabulary deliberately describes only runtime facts. The public
/// The public target maps these values to its stable construction-error
/// contract at the boundary.
package enum RuntimeConstructionError: Error, Sendable {
    case typeIsNotProtocol(typeDescription: String)
    case unsupportedTypeKind(typeName: String)
    case unsupportedProtocolShape(protocolName: String, reason: String)
    case noConformanceFound(protocolName: String)
    case signatureDiscoveryFailed(
        protocolName: String,
        requirementIndex: Int,
        details: String
    )
    case requirementCountMismatch(
        protocolName: String,
        expected: Int,
        actual: Int
    )
    case trampolineAllocationFailed(requirementIndex: Int)
}

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
    case requirementMismatch(
        protocolName: String,
        requirementIndex: Int,
        expected: String,
        actual: String
    )
    /// A forwarding transport limitation expressed without public-double
    /// terminology. The public target maps this to its stable forwarding diagnostic.
    case forwardingUnsupported(
        protocolName: String,
        reason: RuntimeForwardingUnsupportedReason
    )
    case trampolineAllocationFailed(requirementIndex: Int)
}

package enum RuntimeForwardingUnsupportedReason: Sendable {
    case pairedLegacyReadAndYieldingBorrow
    case nonInstanceRequirement(index: Int)
    case simd(index: Int)
    case functionValues(index: Int)
    case outgoingStackWords(index: Int, limit: Int)
    case dynamicSelfResult(index: Int)
    case selfArguments(index: Int)
    case hiddenArguments(index: Int)
}

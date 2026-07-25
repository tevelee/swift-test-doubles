/// Failures reported while constructing a runtime-generated conformance.
///
/// This vocabulary deliberately describes only runtime facts. The public
/// `TestDoubles` target maps these values to its user-facing `StubError`
/// contract at the construction boundary.
package enum RuntimeConstructionError: Error, Sendable {
    case typeIsNotProtocol(typeDescription: String)
    case unsupportedProtocolShape(protocolName: String, reason: String)
    case noConformanceFound(protocolName: String)
    case signatureDiscoveryFailed(
        protocolName: String,
        requirementIndex: Int,
        details: String
    )
}

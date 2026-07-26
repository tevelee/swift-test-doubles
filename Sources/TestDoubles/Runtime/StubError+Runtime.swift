import TestDoublesRuntime
import TestDoublesRuntimeMetadata

extension StubError {
    /// Converts a package-only runtime construction failure into the stable
    /// public error vocabulary without leaking the runtime error type.
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

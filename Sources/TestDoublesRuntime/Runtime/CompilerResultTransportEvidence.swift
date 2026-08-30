import InternalRuntimeContract

/// Immutable compiler-emitted result-transport facts, indexed independently
/// of any top-level protocol requirement so recursive planners can reuse them.
package struct CompilerResultTransportEvidenceCatalog: @unchecked Sendable {
    package static let empty = Self([])

    private let evidence: [RuntimeCompilerResultTransportEvidence]

    package init(_ adapters: [RuntimeAutomaticRequirementAdapter]) {
        evidence = adapters.map(\.resultTransportEvidence)
    }

    package func evidence(
        for resultType: Any.Type,
        isThrowing: Bool,
        isAsync: Bool
    ) -> RuntimeCompilerResultTransportEvidence? {
        evidence.first {
            $0.matches(
                resultType: resultType,
                isThrowing: isThrowing,
                isAsync: isAsync
            )
        }
    }
}

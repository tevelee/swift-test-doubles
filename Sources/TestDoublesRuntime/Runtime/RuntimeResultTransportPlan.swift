/// Construction-time decisions needed to move one witness result out of the
/// generic recorder boundary.
package struct RuntimeResultTransportPlan: Sendable {
    package let requiresFunctionReabstraction: Bool
    package let functionReabstraction: PreparedFunctionReabstraction?

    package init(
        resultType: Any.Type,
        resultTransportEvidenceCatalog: CompilerResultTransportEvidenceCatalog = .empty
    ) {
        functionReabstraction = FunctionReabstraction.prepare(
            type: resultType,
            direction: .genericToDirect,
            resultTransportEvidenceCatalog: resultTransportEvidenceCatalog
        )
        requiresFunctionReabstraction =
            functionReabstraction != nil
            || FunctionReabstraction.requiresStructuralReabstraction(resultType)
    }
}

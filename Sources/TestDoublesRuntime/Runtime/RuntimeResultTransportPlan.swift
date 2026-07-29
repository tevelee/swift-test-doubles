import TestDoublesRuntimeMetadata
/// Construction-time decisions needed to move one witness result out of the
/// generic recorder boundary.
package struct RuntimeResultTransportPlan: Sendable {
    package let requiresFunctionReabstraction: Bool
    package let functionReabstraction: PreparedFunctionReabstraction?

    package init(resultType: Any.Type) {
        functionReabstraction = FunctionReabstraction.prepare(
            type: resultType,
            direction: .genericToDirect
        )
        requiresFunctionReabstraction =
            functionReabstraction != nil
            || FunctionReabstraction.requiresStructuralReabstraction(resultType)
    }
}

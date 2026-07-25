/// Construction-time decisions needed to move one witness result out of the
/// generic recorder boundary.
package struct RuntimeResultTransportPlan: Sendable {
    package let requiresFunctionReabstraction: Bool

    package init(resultType: Any.Type) {
        requiresFunctionReabstraction =
            FunctionReabstraction.requiresStructuralReabstraction(resultType)
    }
}

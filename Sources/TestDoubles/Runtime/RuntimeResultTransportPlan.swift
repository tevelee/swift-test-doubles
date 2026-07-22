/// Construction-time decisions needed to move one witness result out of the
/// generic recorder boundary.
struct RuntimeResultTransportPlan: Sendable {
    let requiresFunctionReabstraction: Bool

    init(resultType: Any.Type) {
        requiresFunctionReabstraction =
            FunctionReabstraction.requiresStructuralReabstraction(resultType)
    }
}

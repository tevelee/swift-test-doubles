/// The concrete typed-error channel, including the ABI decision that selects
/// a distinct caller-provided result slot.
struct TypedErrorTransport: Sendable {
    let type: Any.Type
    let layout: ABIClass
    let dependency: WitnessValueDependency
    let usesIndirectResultSlot: Bool
}

/// Effects that change witness dispatch and result transport.
///
/// This immutable reference also keeps compatibility projections from
/// borrowing nested optional payloads through `MethodDescriptor`, a pattern
/// that Swift 6.3's optimized CopyPropagation pass rejects.
final class RequirementEffects: Sendable {
    struct Throwing: Sendable {
        let isThrowing: Bool
        let isReliable: Bool
        let typedError: TypedErrorTransport?

        static func nonthrowing(reliable: Bool) -> Self {
            Self(
                isThrowing: false,
                isReliable: reliable,
                typedError: nil
            )
        }

        static func untyped(reliable: Bool) -> Self {
            Self(
                isThrowing: true,
                isReliable: reliable,
                typedError: nil
            )
        }

        static func typed(_ transport: TypedErrorTransport) -> Self {
            Self(
                isThrowing: true,
                isReliable: true,
                typedError: transport
            )
        }
    }

    let isAsync: Bool
    let throwing: Throwing

    init(isAsync: Bool, throwing: Throwing) {
        self.isAsync = isAsync
        self.throwing = throwing
    }
}

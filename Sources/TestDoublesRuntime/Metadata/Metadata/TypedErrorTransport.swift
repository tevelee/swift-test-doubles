/// The concrete typed-error channel, including the ABI decision that selects
/// a distinct caller-provided result slot.
package struct TypedErrorTransport: Sendable {
    package let type: Any.Type
    package let layout: ABIClass
    package let dependency: WitnessValueDependency
    package let usesIndirectResultSlot: Bool
}

/// Effects that change witness dispatch and result transport.
///
/// This immutable reference also keeps compatibility projections from
/// borrowing nested optional payloads through `MethodDescriptor`, a pattern
/// that Swift 6.3's optimized CopyPropagation pass rejects.
package final class RequirementEffects: Sendable {
    package struct Throwing: Sendable {
        package let isThrowing: Bool
        package let isReliable: Bool
        package let typedError: TypedErrorTransport?

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

    package let isAsync: Bool
    package let throwing: Throwing

    package init(isAsync: Bool, throwing: Throwing) {
        self.isAsync = isAsync
        self.throwing = throwing
    }
}

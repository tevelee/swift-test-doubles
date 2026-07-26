/// The semantic category of a protocol requirement.
///
/// This is intentionally independent of a witness-table representation. The
/// public recorder uses it to choose behavior and produce diagnostics; the ABI
/// runtime maps it to the corresponding low-level requirement kind.
package enum RuntimeRequirementKind: String, Hashable, Sendable {
    case method
    case initializer
    case getter
    case setter
}

/// The semantic receiver of a protocol requirement.
package enum RuntimeRequirementReceiver: String, Sendable {
    case instance
    case metatype
}

/// How a requirement became part of a generated double.
package enum RuntimeRequirementOrigin: Equatable, Sendable {
    case automatic
    case explicit
    case manual
}

/// The source-level convention of a value in a requirement signature.
///
/// This describes user-visible type relationships only. Layout, indirection,
/// and dependent-witness transport are deliberately runtime implementation
/// details.
package enum RuntimeValueConvention: Equatable, Sendable {
    case concrete
    case associatedType(name: String)
    case selfType
    case optionalSelf
}

/// The semantic ownership intent of a requirement argument.
package enum RuntimeArgumentOwnership: String, Equatable, Sendable {
    case borrowed
    case owned
}

/// A package-only, ABI-free projection of a requirement used by the public
/// recording and diagnostics layers.
///
/// The dense `slot` is an endpoint dispatch identity, not a witness-table
/// index. `witnessSlot` remains useful for diagnostics and manual routing, but
/// it does not expose a witness-table layout or any ABI transport decision.
package struct RuntimeMethod: @unchecked Sendable {
    package let kind: RuntimeRequirementKind
    package let receiver: RuntimeRequirementReceiver
    package let origin: RuntimeRequirementOrigin
    package let name: String
    package let slot: Int
    package let witnessSlot: Int
    package let argumentTypes: [Any.Type]
    package let argumentConventions: [RuntimeValueConvention]
    package let argumentOwnerships: [RuntimeArgumentOwnership]
    package let returnType: Any.Type
    package let returnConvention: RuntimeValueConvention
    package let typedErrorType: Any.Type?
    package let isThrowing: Bool
    package let isAsync: Bool
    package let hasReliableThrowing: Bool
    package let signatureDescription: String

    package init(
        kind: RuntimeRequirementKind,
        receiver: RuntimeRequirementReceiver,
        origin: RuntimeRequirementOrigin,
        name: String,
        slot: Int,
        witnessSlot: Int,
        argumentTypes: [Any.Type],
        argumentConventions: [RuntimeValueConvention],
        argumentOwnerships: [RuntimeArgumentOwnership],
        returnType: Any.Type,
        returnConvention: RuntimeValueConvention,
        typedErrorType: Any.Type?,
        isThrowing: Bool,
        isAsync: Bool,
        hasReliableThrowing: Bool,
        signatureDescription: String
    ) {
        precondition(argumentTypes.count == argumentConventions.count)
        precondition(argumentTypes.count == argumentOwnerships.count)

        self.kind = kind
        self.receiver = receiver
        self.origin = origin
        self.name = name
        self.slot = slot
        self.witnessSlot = witnessSlot
        self.argumentTypes = argumentTypes
        self.argumentConventions = argumentConventions
        self.argumentOwnerships = argumentOwnerships
        self.returnType = returnType
        self.returnConvention = returnConvention
        self.typedErrorType = typedErrorType
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.hasReliableThrowing = hasReliableThrowing
        self.signatureDescription = signatureDescription
    }
}

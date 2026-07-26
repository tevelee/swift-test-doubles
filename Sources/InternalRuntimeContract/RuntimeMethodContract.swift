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

/// The source-level positions in which a value depends on an associated type.
///
/// Unlike the runtime's descriptor graph, this has no metadata identity or
/// layout decision. It preserves enough requirement schema to validate and
/// diagnose explicit requirements without exposing witness transport.
package indirect enum RuntimeValueDependency: Equatable, Sendable {
    case independent
    case associatedType(name: String)
    case referenceAssociatedType(name: String)
    case optional(RuntimeValueDependency)
    case array(RuntimeValueDependency)
    case set(RuntimeValueDependency)
    case dictionary(key: RuntimeValueDependency, value: RuntimeValueDependency)
    case result(success: RuntimeValueDependency, failure: RuntimeValueDependency)
    case genericClass(name: String, arguments: [RuntimeValueDependency])

    /// Convenience construction for source-level schemas and tests.
    package static func associatedType(_ name: String) -> Self {
        .associatedType(name: name)
    }

    /// Convenience construction for dictionary schemas that name direct
    /// associated-type positions only.
    package static func dictionary(key: String?, value: String?) -> Self {
        .dictionary(
            key: key.map(Self.associatedType) ?? .independent,
            value: value.map(Self.associatedType) ?? .independent
        )
    }

    /// The compatibility projection used by scalar method summaries.
    /// Full structural relationships remain on ``RuntimeValue/dependency``.
    package var legacyProjection: Self {
        switch self {
            case .independent:
                .independent
            case .associatedType(let name), .referenceAssociatedType(let name):
                .associatedType(name: name)
            case .optional(let wrapped), .array(let wrapped), .set(let wrapped):
                wrapped.legacyProjection
            case .dictionary(let key, let value):
                .dictionary(
                    key: key.legacyProjection,
                    value: value.legacyProjection
                )
            case .result(let success, let failure):
                .result(
                    success: success.legacyProjection,
                    failure: failure.legacyProjection
                )
            case .genericClass(let name, let arguments):
                .genericClass(
                    name: name,
                    arguments: arguments.map(\.legacyProjection)
                )
        }
    }
}

/// The source-level description of one requirement value.
package struct RuntimeValue: @unchecked Sendable {
    package let type: Any.Type
    package let convention: RuntimeValueConvention
    package let dependency: RuntimeValueDependency

    package init(
        type: Any.Type,
        convention: RuntimeValueConvention,
        dependency: RuntimeValueDependency
    ) {
        self.type = type
        self.convention = convention
        self.dependency = dependency
    }
}

/// One source-level argument of a requirement.
package struct RuntimeArgument: @unchecked Sendable {
    package let value: RuntimeValue
    package let ownership: RuntimeArgumentOwnership

    package init(value: RuntimeValue, ownership: RuntimeArgumentOwnership) {
        self.value = value
        self.ownership = ownership
    }
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
    package let arguments: [RuntimeArgument]
    package let result: RuntimeValue
    package let typedErrorType: Any.Type?
    package let typedErrorDependency: RuntimeValueDependency?
    /// A source-level class constraint on `Self`; layout remains runtime-owned.
    package let selfIsClassConstrained: Bool
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
        arguments: [RuntimeArgument],
        result: RuntimeValue,
        typedErrorType: Any.Type?,
        typedErrorDependency: RuntimeValueDependency?,
        selfIsClassConstrained: Bool,
        isThrowing: Bool,
        isAsync: Bool,
        hasReliableThrowing: Bool,
        signatureDescription: String
    ) {
        self.kind = kind
        self.receiver = receiver
        self.origin = origin
        self.name = name
        self.slot = slot
        self.witnessSlot = witnessSlot
        self.arguments = arguments
        self.result = result
        self.typedErrorType = typedErrorType
        self.typedErrorDependency = typedErrorDependency
        self.selfIsClassConstrained = selfIsClassConstrained
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.hasReliableThrowing = hasReliableThrowing
        self.signatureDescription = signatureDescription
    }

    /// Backward-compatible local spelling for the recorder's dispatch slot.
    package var index: Int { slot }

    /// Backward-compatible local spelling for the requirement's source slot.
    package var witnessIndex: Int { witnessSlot }

    package var argumentTypes: [Any.Type] { arguments.map(\.value.type) }
    package var argumentConventions: [RuntimeValueConvention] {
        arguments.map(\.value.convention)
    }
    package var argumentOwnerships: [RuntimeArgumentOwnership] {
        arguments.map(\.ownership)
    }
    package var argumentDependencies: [RuntimeValueDependency] {
        arguments.map { $0.value.dependency.legacyProjection }
    }
    package var returnType: Any.Type { result.type }
    package var returnConvention: RuntimeValueConvention { result.convention }
    package var returnDependency: RuntimeValueDependency {
        result.dependency.legacyProjection
    }
}

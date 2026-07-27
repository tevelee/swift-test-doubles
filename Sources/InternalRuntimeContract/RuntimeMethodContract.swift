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
    /// A value typed by the requirement's own generic parameter, resolved per
    /// call site. `index` counts distinct requirement-level generic
    /// parameters in declaration order.
    case methodGenericParameter(index: Int)
}

/// The semantic ownership intent of a requirement argument.
package enum RuntimeArgumentOwnership: String, Equatable, Sendable {
    case borrowed
    case owned
}

/// The associated types used by one source-level requirement value.
///
/// This ordered summary intentionally omits the type expression that contains
/// each use and all witness transport details. The metadata runtime keeps that
/// information in its private descriptor graph; recording and diagnostics
/// need only know whether a value is dependent and which names it uses.
package struct RuntimeAssociatedTypeUse: Equatable, Sendable {
    /// Associated-type names in source order, with later duplicates removed.
    package let names: [String]

    package init(names: [String]) {
        var seen = Set<String>()
        self.names = names.filter { seen.insert($0).inserted }
    }

    /// A value that does not use an associated type.
    package static let none = Self(names: [])

    /// A value that uses one named associated type.
    package static func associatedType(named name: String) -> Self {
        Self(names: [name])
    }

    package var isDependent: Bool {
        names.isEmpty == false
    }

    package var firstName: String? {
        names.first
    }
}

/// The source-level description of one requirement value.
package struct RuntimeValue: @unchecked Sendable {
    package let type: Any.Type
    package let convention: RuntimeValueConvention
    package let associatedTypeUse: RuntimeAssociatedTypeUse

    package init(
        type: Any.Type,
        convention: RuntimeValueConvention,
        associatedTypeUse: RuntimeAssociatedTypeUse
    ) {
        self.type = type
        self.convention = convention
        self.associatedTypeUse = associatedTypeUse
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
/// index. Witness-table coordinates remain entirely within Metadata and
/// execution, where they are required to fabricate ABI entries.
package struct RuntimeMethod: @unchecked Sendable {
    package let kind: RuntimeRequirementKind
    package let receiver: RuntimeRequirementReceiver
    package let origin: RuntimeRequirementOrigin
    package let name: String
    package let slot: Int
    package let arguments: [RuntimeArgument]
    package let result: RuntimeValue
    package let typedErrorType: Any.Type?
    package let typedErrorAssociatedTypeUse: RuntimeAssociatedTypeUse?
    /// A source-level class constraint on `Self`; layout remains runtime-owned.
    package let selfIsClassConstrained: Bool
    package let isThrowing: Bool
    package let isAsync: Bool
    package let hasReliableThrowing: Bool
    private let suppliedSignatureDescription: String?

    package init(
        kind: RuntimeRequirementKind,
        receiver: RuntimeRequirementReceiver,
        origin: RuntimeRequirementOrigin,
        name: String,
        slot: Int,
        arguments: [RuntimeArgument],
        result: RuntimeValue,
        typedErrorType: Any.Type?,
        typedErrorAssociatedTypeUse: RuntimeAssociatedTypeUse?,
        selfIsClassConstrained: Bool,
        isThrowing: Bool,
        isAsync: Bool,
        hasReliableThrowing: Bool,
        signatureDescription: String? = nil
    ) {
        self.kind = kind
        self.receiver = receiver
        self.origin = origin
        self.name = name
        self.slot = slot
        self.arguments = arguments
        self.result = result
        self.typedErrorType = typedErrorType
        self.typedErrorAssociatedTypeUse = typedErrorAssociatedTypeUse
        self.selfIsClassConstrained = selfIsClassConstrained
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.hasReliableThrowing = hasReliableThrowing
        suppliedSignatureDescription = signatureDescription
    }

    /// Backward-compatible local spelling for the recorder's dispatch slot.
    package var index: Int { slot }

    package var argumentTypes: [Any.Type] { arguments.map(\.value.type) }
    package var argumentConventions: [RuntimeValueConvention] {
        arguments.map(\.value.convention)
    }
    package var argumentOwnerships: [RuntimeArgumentOwnership] {
        arguments.map(\.ownership)
    }
    package var argumentAssociatedTypeUses: [RuntimeAssociatedTypeUse] {
        arguments.map(\.value.associatedTypeUse)
    }
    package var returnType: Any.Type { result.type }
    package var returnConvention: RuntimeValueConvention { result.convention }
    package var returnAssociatedTypeUse: RuntimeAssociatedTypeUse {
        result.associatedTypeUse
    }

    /// A human-readable requirement signature used only by diagnostics.
    ///
    /// Discovered methods are created on every fabricated-double construction.
    /// Keep string formatting out of that path and derive it only when a
    /// validation or diagnostic needs it. Manual routes can still retain their
    /// explicit spelling.
    package var signatureDescription: String {
        suppliedSignatureDescription ?? runtimeMethodSignatureDescription(self)
    }
}

private func runtimeMethodSignatureDescription(_ method: RuntimeMethod) -> String {
    let typedErrorDescription = method.typedErrorType.map {
        runtimeTypedErrorDescription(
            type: $0,
            associatedTypeUse: method.typedErrorAssociatedTypeUse ?? .none
        )
    }
    let throwingEffect =
        typedErrorDescription.map { "throws(\($0))" }
        ?? (method.isThrowing ? "throws" : nil)
    let effectDescription = [method.isAsync ? "async" : nil, throwingEffect]
        .compactMap { $0 }
        .joined(separator: " ")
    let effectSuffix = effectDescription.isEmpty ? "" : " \(effectDescription)"
    let uncertaintySuffix = method.hasReliableThrowing ? "" : " [throwing effect unavailable]"
    let resultDescription = runtimeValueDescription(method.result)

    switch method.kind {
        case .method:
            let arguments = method.arguments.map(runtimeArgumentDescription).joined(separator: ", ")
            return "method (\(arguments))\(effectSuffix)\(uncertaintySuffix) -> \(resultDescription)"
        case .initializer:
            let arguments = method.arguments.map(runtimeArgumentDescription).joined(separator: ", ")
            return "initializer (\(arguments))\(effectSuffix) -> \(resultDescription)"
        case .getter:
            let indices = method.arguments.map(runtimeArgumentDescription).joined(separator: ", ")
            let indexSuffix = indices.isEmpty ? "" : " (indices: \(indices))"
            return "getter\(indexSuffix)\(effectSuffix)\(uncertaintySuffix) -> \(resultDescription)"
        case .setter:
            let arguments = method.arguments.map(runtimeArgumentDescription)
            let value = arguments.first ?? "<missing>"
            let indexSuffix =
                arguments.count > 1
                ? ", indices: \(arguments.dropFirst().joined(separator: ", "))"
                : ""
            return "setter (value: \(value)\(indexSuffix)) -> Swift.Void"
    }
}

private func runtimeArgumentDescription(_ argument: RuntimeArgument) -> String {
    let description = runtimeValueDescription(argument.value)
    return argument.ownership == .owned ? "consuming \(description)" : description
}

private func runtimeValueDescription(_ value: RuntimeValue) -> String {
    if value.associatedTypeUse.isDependent {
        return "\(runtimeTypeName(value.type)) [associated \(value.associatedTypeUse.names.joined(separator: ", "))]"
    }

    return switch value.convention {
        case .concrete:
            runtimeTypeName(value.type)
        case .associatedType(let name):
            "\(runtimeTypeName(value.type)) [associated \(name)]"
        case .selfType:
            "Self"
        case .optionalSelf:
            "Self?"
        case .methodGenericParameter(let index):
            "<generic parameter \(index)>"
    }
}

private func runtimeTypedErrorDescription(
    type: Any.Type,
    associatedTypeUse: RuntimeAssociatedTypeUse
) -> String {
    let typeName = runtimeTypeName(type)
    if associatedTypeUse.isDependent {
        return "\(typeName) [associated \(associatedTypeUse.names.joined(separator: ", "))]"
    }
    return typeName
}

private func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}

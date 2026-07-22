import Echo

enum StubRequirementKind: String, Hashable, Sendable {
    case method
    case initializer
    case getter
    case setter

    init?(_ kind: ProtocolRequirement.Kind) {
        switch kind {
            case .method:
                self = .method
            case .`init`:
                self = .initializer
            case .getter:
                self = .getter
            case .setter:
                self = .setter
            default:
                return nil
        }
    }

    func defaultArgumentOwnership(at offset: Int) -> WitnessArgumentOwnership {
        switch self {
            case .setter:
                offset == 0 ? .owned : .borrowed
            case .initializer:
                .owned
            case .method, .getter:
                .borrowed
        }
    }
}

enum StubRequirementReceiver: String, Sendable {
    case instance
    case metatype
}

enum WitnessValueConvention: Equatable, Sendable {
    case concrete
    case associatedType(name: String)
    case selfType
    case optionalSelf
}

enum WitnessArgumentOwnership: String, Equatable, Sendable {
    case borrowed
    case owned
}

/// The runtime type, semantic convention, dependency, and ABI transport for
/// one value in a protocol witness call.
struct WitnessValueDescriptor: Sendable {
    let type: Any.Type
    let convention: WitnessValueConvention
    let dependency: WitnessValueDependency
    let layout: ABIClass
}

/// An incoming witness value and the ownership convention applied after it is
/// decoded from the call frame.
struct WitnessArgumentDescriptor: Sendable {
    let value: WitnessValueDescriptor
    let ownership: WitnessArgumentOwnership
}

extension WitnessValueDescriptor {
    /// Whether both values describe the same runtime type, semantic
    /// convention, and dependency. ABI layout follows from those inputs.
    func matches(_ other: Self) -> Bool {
        sameType(type, other.type)
            && convention == other.convention
            && dependency == other.dependency
    }
}

extension WitnessArgumentDescriptor {
    func matches(_ other: Self) -> Bool {
        value.matches(other.value) && ownership == other.ownership
    }
}

/// Concrete metadata paired with the source-level associated-type positions
/// that produced it.
struct ResolvedDependentType: Sendable {
    let type: Any.Type
    let dependency: WitnessValueDependency

    func optional() -> Self {
        Self(
            type: _openExistential(type, do: optionalType),
            dependency: .optional(dependency)
        )
    }

    func array() -> Self {
        Self(
            type: _openExistential(type, do: arrayType),
            dependency: .array(dependency)
        )
    }

    func set(
        protocolName: String,
        sourceDescription: String
    ) throws -> Self {
        guard let type = setType(of: type) else {
            let reason: String
            if let name = dependency.directAssociatedTypeName {
                reason =
                    "Associated type '\(name)' is used as a Set element, but "
                    + "its concrete binding '\(runtimeTypeName(self.type))' does "
                    + "not conform to Hashable. Bind '\(name)' to a Hashable "
                    + "concrete type."
            } else {
                reason =
                    "Set element '\(sourceDescription)' resolves to "
                    + "'\(runtimeTypeName(self.type))', which does not conform "
                    + "to Hashable."
            }
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
        return Self(type: type, dependency: .set(dependency))
    }

    static func dictionary(
        key: Self,
        value: Self,
        protocolName: String
    ) throws -> Self {
        guard let type = dictionaryType(key: key.type, value: value.type) else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Dictionary key '\(runtimeTypeName(key.type))' does not conform to Hashable. Bind its associated type to a Hashable concrete type."
            )
        }
        return Self(
            type: type,
            dependency: .dictionary(
                key: key.dependency,
                value: value.dependency
            )
        )
    }

    static func result(
        success: Self,
        failure: Self,
        protocolName: String
    ) throws -> Self {
        guard
            let type = resultType(
                success: success.type,
                failure: failure.type
            )
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Result failure '\(runtimeTypeName(failure.type))' does not conform to Error."
            )
        }
        return Self(
            type: type,
            dependency: .result(
                success: success.dependency,
                failure: failure.dependency
            )
        )
    }
}

/// A value resolved from either an explicit requirement or an automatically
/// discovered witness signature before its ABI layout is classified.
struct ResolvedWitnessValue: Sendable {
    let type: Any.Type
    let convention: WitnessValueConvention
    let dependency: WitnessValueDependency
    let ownership: WitnessArgumentOwnership?

    func argumentOwnership(
        for kind: StubRequirementKind,
        at offset: Int
    ) -> WitnessArgumentOwnership {
        ownership ?? kind.defaultArgumentOwnership(at: offset)
    }

    static func resolved(
        _ value: ResolvedDependentType,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        let convention: WitnessValueConvention
        if value.dependency.usesOpaqueValueWitnessConvention,
            let name = value.dependency.firstAssociatedTypeName
        {
            convention = .associatedType(name: name)
        } else {
            convention = .concrete
        }
        return Self(
            type: value.type,
            convention: convention,
            dependency: value.dependency,
            ownership: ownership
        )
    }

    /// The dynamic `Self` value transported through `StubPayload` storage.
    static func selfValue(
        isOptional: Bool,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        Self(
            type: isOptional ? Optional<StubPayload>.self : StubPayload.self,
            convention: isOptional ? .optionalSelf : .selfType,
            dependency: .independent,
            ownership: ownership
        )
    }
}

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

struct MethodDescriptor: Sendable {
    enum Origin: Equatable, Sendable {
        case automatic
        case explicit
        case manual
    }

    let kind: StubRequirementKind
    let receiver: StubRequirementReceiver
    let origin: Origin
    let name: String
    /// Dense identifier used by the recorder and trampoline handler.
    let index: Int
    /// Slot in the declaring protocol's witness table.
    let witnessIndex: Int
    let arguments: [WitnessArgumentDescriptor]
    let result: WitnessValueDescriptor
    let effects: RequirementEffects
    let typedWitnessAdapterFactory: TypedWitnessAdapterFactory?

    init(
        kind: StubRequirementKind,
        receiver: StubRequirementReceiver = .instance,
        origin: Origin = .automatic,
        name: String,
        index: Int,
        witnessIndex: Int? = nil,
        argumentTypes: [Any.Type],
        returnType: Any.Type,
        argumentConventions: [WitnessValueConvention]? = nil,
        argumentDependencies: [WitnessValueDependency]? = nil,
        argumentOwnerships: [WitnessArgumentOwnership]? = nil,
        returnConvention: WitnessValueConvention = .concrete,
        returnDependency: WitnessValueDependency? = nil,
        typedErrorType: Any.Type? = nil,
        typedErrorDependency: WitnessValueDependency = .independent,
        selfIsClassConstrained: Bool = false,
        isThrowing: Bool = false,
        isAsync: Bool = false,
        hasReliableThrowing: Bool = true,
        typedWitnessAdapterFactory: TypedWitnessAdapterFactory? = nil
    ) {
        self.kind = kind
        self.receiver = receiver
        self.origin = origin
        self.name = name
        self.index = index
        self.witnessIndex = witnessIndex ?? index

        let conventions =
            argumentConventions
            ?? Array(repeating: .concrete, count: argumentTypes.count)
        let dependencies =
            argumentDependencies
            ?? conventions.map(Self.defaultDependency(for:))
        let ownerships =
            argumentOwnerships
            ?? argumentTypes.indices.map(kind.defaultArgumentOwnership(at:))

        precondition(conventions.count == argumentTypes.count)
        precondition(dependencies.count == argumentTypes.count)
        precondition(ownerships.count == argumentTypes.count)

        arguments = argumentTypes.indices.map { offset in
            let type = argumentTypes[offset]
            let convention = conventions[offset]
            return WitnessArgumentDescriptor(
                value: WitnessValueDescriptor(
                    type: type,
                    convention: convention,
                    dependency: dependencies[offset],
                    layout: Self.argumentLayout(
                        for: type,
                        convention: convention,
                        dependency: dependencies[offset]
                    )
                ),
                ownership: ownerships[offset]
            )
        }

        let resultDependency =
            returnDependency ?? Self.defaultDependency(for: returnConvention)
        let resultLayout = Self.resultLayout(
            for: returnType,
            convention: returnConvention,
            dependency: resultDependency,
            selfIsClassConstrained: selfIsClassConstrained
        )
        result = WitnessValueDescriptor(
            type: returnType,
            convention: returnConvention,
            dependency: resultDependency,
            layout: resultLayout
        )

        let throwing: RequirementEffects.Throwing
        if let typedErrorType {
            precondition(
                isThrowing,
                "[TestDoubles] A typed-error transport requires a throwing requirement."
            )
            let errorLayout = abiClass(for: typedErrorType, isReturn: true)
            let concreteLayoutUsesIndirectResultSlot =
                switch (resultLayout, errorLayout) {
                    case (.indirect, _), (_, .indirect): true
                    default: false
                }
            let usesIndirectResultSlot =
                typedErrorDependency.usesOpaqueValueWitnessConvention
                || concreteLayoutUsesIndirectResultSlot
            throwing = .typed(
                TypedErrorTransport(
                    type: typedErrorType,
                    layout: errorLayout,
                    dependency: typedErrorDependency,
                    usesIndirectResultSlot: usesIndirectResultSlot
                ))
        } else if isThrowing {
            precondition(
                typedErrorDependency == .independent,
                "[TestDoubles] A typed-error dependency requires error metadata."
            )
            throwing = .untyped(reliable: hasReliableThrowing)
        } else {
            throwing = .nonthrowing(reliable: hasReliableThrowing)
        }
        effects = RequirementEffects(isAsync: isAsync, throwing: throwing)
        self.typedWitnessAdapterFactory = typedWitnessAdapterFactory
    }

    /// Builds a descriptor from resolved witness values, applying each
    /// requirement kind's default argument ownership and rejecting a
    /// consuming result.
    init(
        kind: StubRequirementKind,
        receiver: StubRequirementReceiver,
        origin: Origin = .automatic,
        name: String,
        index: Int,
        witnessIndex: Int,
        arguments: [ResolvedWitnessValue],
        result: ResolvedWitnessValue,
        protocolName: String,
        typedErrorType: Any.Type? = nil,
        typedErrorDependency: WitnessValueDependency = .independent,
        selfIsClassConstrained: Bool,
        isThrowing: Bool,
        isAsync: Bool,
        hasReliableThrowing: Bool = true,
        typedWitnessAdapterFactory: TypedWitnessAdapterFactory? = nil
    ) throws {
        guard result.ownership == nil else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Requirement \(index) marks a result as consuming. Ownership applies only to arguments."
            )
        }
        let unsupportedReferenceDependencies =
            arguments.map(\.dependency) + [result.dependency]
        guard
            unsupportedReferenceDependencies.allSatisfy(
                \.usesSupportedReferenceAssociatedTransport
            )
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason:
                    "Requirement \(index) embeds an AnyObject-constrained associated type in an unsupported value shape. "
                    + "Only direct values and one Optional layer have a proven dependent reference ABI."
            )
        }
        self.init(
            kind: kind,
            receiver: receiver,
            origin: origin,
            name: name,
            index: index,
            witnessIndex: witnessIndex,
            argumentTypes: arguments.map(\.type),
            returnType: result.type,
            argumentConventions: arguments.map(\.convention),
            argumentDependencies: arguments.map(\.dependency),
            argumentOwnerships: arguments.enumerated().map { offset, argument in
                argument.argumentOwnership(for: kind, at: offset)
            },
            returnConvention: result.convention,
            returnDependency: result.dependency,
            typedErrorType: typedErrorType,
            typedErrorDependency: typedErrorDependency,
            selfIsClassConstrained: selfIsClassConstrained,
            isThrowing: isThrowing,
            isAsync: isAsync,
            hasReliableThrowing: hasReliableThrowing,
            typedWitnessAdapterFactory: typedWitnessAdapterFactory
        )
    }

    // Convenience projections over the typed model. The scalar accessors are
    // used throughout the runtime; the per-argument arrays remain for
    // descriptor-focused tests.
    var argumentTypes: [Any.Type] { arguments.map(\.value.type) }
    var returnType: Any.Type { result.type }
    var argumentConventions: [WitnessValueConvention] {
        arguments.map(\.value.convention)
    }
    var argumentDependencies: [WitnessValueDependency] {
        arguments.map { $0.value.dependency.legacyProjection }
    }
    var argumentOwnerships: [WitnessArgumentOwnership] {
        arguments.map(\.ownership)
    }
    var returnConvention: WitnessValueConvention { result.convention }
    var returnDependency: WitnessValueDependency {
        result.dependency.legacyProjection
    }
    var argumentLayouts: [ABIClass] { arguments.map(\.value.layout) }
    var returnLayout: ABIClass { result.layout }
    var typedErrorType: Any.Type? { effects.throwing.typedError?.type }
    var typedErrorLayout: ABIClass? { effects.throwing.typedError?.layout }
    var typedErrorDependency: WitnessValueDependency {
        effects.throwing.typedError?.dependency.legacyProjection ?? .independent
    }
    var typedErrorUsesIndirectResultSlot: Bool {
        effects.throwing.typedError?.usesIndirectResultSlot ?? false
    }
    var isThrowing: Bool { effects.throwing.isThrowing }
    var isAsync: Bool { effects.isAsync }
    var hasReliableThrowing: Bool { effects.throwing.isReliable }

    var signatureDescription: String {
        let throwingEffect =
            effects.throwing.typedError.map {
                "throws(\(typedErrorDescription($0)))"
            } ?? (isThrowing ? "throws" : nil)
        let effectDescription = [isAsync ? "async" : nil, throwingEffect]
            .compactMap { $0 }
            .joined(separator: " ")
        let effectSuffix = effectDescription.isEmpty ? "" : " \(effectDescription)"
        let uncertaintySuffix = hasReliableThrowing ? "" : " [throwing effect unavailable]"
        let resultDescription = witnessValueDescription(result)

        switch kind {
            case .method:
                let arguments = arguments.map(witnessArgumentDescription).joined(separator: ", ")
                return "method (\(arguments))\(effectSuffix)\(uncertaintySuffix) -> \(resultDescription)"
            case .initializer:
                let arguments = arguments.map(witnessArgumentDescription).joined(separator: ", ")
                return "initializer (\(arguments))\(effectSuffix) -> \(resultDescription)"
            case .getter:
                let indices = arguments.map(witnessArgumentDescription).joined(separator: ", ")
                let indexSuffix = indices.isEmpty ? "" : " (indices: \(indices))"
                return "getter\(indexSuffix)\(effectSuffix)\(uncertaintySuffix) -> \(resultDescription)"
            case .setter:
                let arguments = arguments.map(witnessArgumentDescription)
                let value = arguments.first ?? "<missing>"
                let indexSuffix =
                    arguments.count > 1
                    ? ", indices: \(arguments.dropFirst().joined(separator: ", "))"
                    : ""
                return "setter (value: \(value)\(indexSuffix)) -> Swift.Void"
        }
    }

    func hasSameSignature(as discovered: Self) -> Bool {
        let typedErrorsMatch: Bool
        switch (
            effects.throwing.typedError,
            discovered.effects.throwing.typedError
        ) {
            case (nil, nil):
                typedErrorsMatch = true
            case (.some(let lhs), .some(let rhs)):
                typedErrorsMatch =
                    sameType(lhs.type, rhs.type)
                    && lhs.dependency == rhs.dependency
            case (.none, .some), (.some, .none):
                typedErrorsMatch = false
        }
        let effectsMatch =
            isAsync == discovered.isAsync
            && (discovered.hasReliableThrowing == false
                || isThrowing == discovered.isThrowing)
            && typedErrorsMatch
        return kind == discovered.kind
            && receiver == discovered.receiver
            && effectsMatch
            && result.matches(discovered.result)
            && arguments.count == discovered.arguments.count
            && zip(arguments, discovered.arguments).allSatisfy { $0.matches($1) }
    }

    private static func defaultDependency(
        for convention: WitnessValueConvention
    ) -> WitnessValueDependency {
        if case .associatedType(let name) = convention {
            return .associatedType(name: name)
        }
        return .independent
    }

    private static func argumentLayout(
        for type: Any.Type,
        convention: WitnessValueConvention,
        dependency: WitnessValueDependency
    ) -> ABIClass {
        if dependency.usesOpaqueValueWitnessConvention {
            return .indirect
        }
        return switch convention {
            case .concrete: abiClass(for: type)
            case .associatedType, .selfType, .optionalSelf: .indirect
        }
    }

    private static func resultLayout(
        for type: Any.Type,
        convention: WitnessValueConvention,
        dependency: WitnessValueDependency,
        selfIsClassConstrained: Bool
    ) -> ABIClass {
        if dependency.usesOpaqueValueWitnessConvention {
            return .indirect
        }
        return switch convention {
            case .concrete: abiClass(for: type, isReturn: true)
            case .associatedType: .indirect
            case .selfType, .optionalSelf:
                selfIsClassConstrained ? .integer(words: 1) : .indirect
        }
    }
}

func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}

private func witnessArgumentDescription(
    _ argument: WitnessArgumentDescriptor
) -> String {
    let description = witnessValueDescription(argument.value)
    return argument.ownership == .owned ? "consuming \(description)" : description
}

private func witnessValueDescription(
    _ value: WitnessValueDescriptor
) -> String {
    switch value.dependency.legacyProjection {
        case .independent:
            break
        case .associatedType(let reference):
            return "\(runtimeTypeName(value.type)) [associated \(reference.name)]"
        case .dictionary(let key, let valueDependency):
            let components = [
                key.directAssociatedTypeName.map { "key \($0)" },
                valueDependency.directAssociatedTypeName.map { "value \($0)" }
            ].compactMap { $0 }.joined(separator: ", ")
            return "\(runtimeTypeName(value.type)) [associated Dictionary \(components)]"
        case .result, .genericClass:
            break
        case .optional, .array, .set:
            break
    }
    return switch value.convention {
        case .concrete: runtimeTypeName(value.type)
        case .associatedType(let name):
            "\(runtimeTypeName(value.type)) [associated \(name)]"
        case .selfType:
            "Self"
        case .optionalSelf:
            "Self?"
    }
}

private func typedErrorDescription(_ error: TypedErrorTransport) -> String {
    let typeName = runtimeTypeName(error.type)
    if let name = error.dependency.directAssociatedTypeName {
        return "\(typeName) [associated \(name)]"
    }
    if case .genericClass = error.dependency {
        return "\(typeName) [associated-dependent generic class]"
    }
    return typeName
}

private func sameType(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

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

enum WitnessValueDependency: Equatable, Sendable {
    case independent
    case associatedType(name: String)
    /// A Dictionary whose key, value, or both are associated types. Keeping
    /// the positions distinct prevents equal concrete substitutions from
    /// erasing the source witness schema during explicit validation.
    case dictionary(key: String?, value: String?)

    var isAssociatedTypeDependent: Bool {
        switch self {
            case .independent: false
            case .associatedType, .dictionary: true
        }
    }
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

/// A supported container position for an associated type occurring in a
/// requirement signature.
enum AssociatedTypeContainer: Sendable {
    case optional
    case array
    case set
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

    /// A direct occurrence of a concretely bound associated type.
    static func associatedType(
        binding: StubProtocolMetadata.AssociatedTypeBinding,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        Self(
            type: binding.type,
            convention: .associatedType(name: binding.name),
            dependency: .associatedType(name: binding.name),
            ownership: ownership
        )
    }

    /// A Dictionary whose key, value, or both depend directly on concretely
    /// bound associated types. Dictionary retains its ordinary direct
    /// reference transport while its generic-argument positions remain part
    /// of strict signature validation.
    static func associatedTypeDictionary(
        keyType: Any.Type,
        keyAssociatedTypeName: String?,
        valueType: Any.Type,
        valueAssociatedTypeName: String?,
        protocolName: String,
        ownership: WitnessArgumentOwnership? = nil
    ) throws -> Self {
        precondition(
            keyAssociatedTypeName != nil || valueAssociatedTypeName != nil,
            "[TestDoubles] A dependent Dictionary needs an associated key or value."
        )
        guard let type = dictionaryType(key: keyType, value: valueType) else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Dictionary key '\(runtimeTypeName(keyType))' does not conform to Hashable. Bind its associated type to a Hashable concrete type."
            )
        }
        return Self(
            type: type,
            convention: .concrete,
            dependency: .dictionary(
                key: keyAssociatedTypeName,
                value: valueAssociatedTypeName
            ),
            ownership: ownership
        )
    }

    /// A supported container whose value depends on a concretely bound
    /// associated type. Optionals keep the dependent-value witness
    /// convention; arrays and sets are transported as ordinary concrete values.
    static func associatedType(
        binding: StubProtocolMetadata.AssociatedTypeBinding,
        container: AssociatedTypeContainer,
        ownership: WitnessArgumentOwnership? = nil
    ) throws -> Self {
        let (type, convention): (Any.Type, WitnessValueConvention)
        switch container {
            case .optional:
                type = _openExistential(binding.type, do: optionalType)
                convention = .associatedType(name: binding.name)
            case .array:
                type = _openExistential(binding.type, do: arrayType)
                convention = .concrete
            case .set:
                guard let resolvedSetType = setType(of: binding.type) else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: binding.protocolDescriptor.name,
                        reason: "Associated type '\(binding.name)' is used as a Set element, but its concrete binding '\(String(reflecting: binding.type))' does not conform to Hashable. Bind '\(binding.name)' to a Hashable concrete type."
                    )
                }
                type = resolvedSetType
                convention = .concrete
        }
        return Self(
            type: type,
            convention: convention,
            dependency: .associatedType(name: binding.name),
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
                    layout: Self.argumentLayout(for: type, convention: convention)
                ),
                ownership: ownerships[offset]
            )
        }

        let resultDependency =
            returnDependency ?? Self.defaultDependency(for: returnConvention)
        let resultLayout = Self.resultLayout(
            for: returnType,
            convention: returnConvention,
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
                typedErrorDependency.isAssociatedTypeDependent
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
        arguments.map(\.value.dependency)
    }
    var argumentOwnerships: [WitnessArgumentOwnership] {
        arguments.map(\.ownership)
    }
    var returnConvention: WitnessValueConvention { result.convention }
    var returnDependency: WitnessValueDependency { result.dependency }
    var argumentLayouts: [ABIClass] { arguments.map(\.value.layout) }
    var returnLayout: ABIClass { result.layout }
    var typedErrorType: Any.Type? { effects.throwing.typedError?.type }
    var typedErrorLayout: ABIClass? { effects.throwing.typedError?.layout }
    var typedErrorDependency: WitnessValueDependency {
        effects.throwing.typedError?.dependency ?? .independent
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
        switch (typedErrorType, discovered.typedErrorType) {
            case (nil, nil):
                typedErrorsMatch = true
            case (.some(let lhs), .some(let rhs)):
                typedErrorsMatch =
                    sameType(lhs, rhs)
                    && typedErrorDependency == discovered.typedErrorDependency
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
        convention: WitnessValueConvention
    ) -> ABIClass {
        switch convention {
            case .concrete: abiClass(for: type)
            case .associatedType, .selfType, .optionalSelf: .indirect
        }
    }

    private static func resultLayout(
        for type: Any.Type,
        convention: WitnessValueConvention,
        selfIsClassConstrained: Bool
    ) -> ABIClass {
        switch convention {
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
    switch value.dependency {
        case .independent:
            break
        case .associatedType(let name):
            return "\(runtimeTypeName(value.type)) [associated \(name)]"
        case .dictionary(let key, let valueName):
            let components = [
                key.map { "key \($0)" },
                valueName.map { "value \($0)" }
            ].compactMap { $0 }.joined(separator: ", ")
            return "\(runtimeTypeName(value.type)) [associated Dictionary \(components)]"
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
    if case .associatedType(let name) = error.dependency {
        return "\(typeName) [associated \(name)]"
    }
    return typeName
}

private func sameType(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

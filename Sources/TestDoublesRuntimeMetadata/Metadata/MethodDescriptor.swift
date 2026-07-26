import InternalRuntimeContract

package struct MethodDescriptor: Sendable {
    package enum Origin: Equatable, Sendable {
        case automatic
        case explicit
        case manual
    }

    package let kind: StubRequirementKind
    package let receiver: StubRequirementReceiver
    package let origin: Origin
    package let name: String
    /// Dense identifier used by the recorder and trampoline handler.
    package let index: Int
    /// Slot in the declaring protocol's witness table.
    package let witnessIndex: Int
    package let arguments: [WitnessArgumentDescriptor]
    package let result: WitnessValueDescriptor
    package let effects: RequirementEffects
    package let selfIsClassConstrained: Bool
    package let typedWitnessAdapterFactory: TypedWitnessAdapterFactory?

    package init(
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
                        dependency: dependencies[offset],
                        selfIsClassConstrained: selfIsClassConstrained
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
        self.selfIsClassConstrained = selfIsClassConstrained
        self.typedWitnessAdapterFactory = typedWitnessAdapterFactory
    }

    /// Builds a descriptor from resolved witness values, applying each
    /// requirement kind's default argument ownership and rejecting a
    /// consuming result.
    package init(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
    package var argumentTypes: [Any.Type] { arguments.map(\.value.type) }
    package var returnType: Any.Type { result.type }
    package var argumentConventions: [WitnessValueConvention] {
        arguments.map(\.value.convention)
    }
    package var argumentDependencies: [WitnessValueDependency] {
        arguments.map { $0.value.dependency.legacyProjection }
    }
    package var argumentOwnerships: [WitnessArgumentOwnership] {
        arguments.map(\.ownership)
    }
    package var returnConvention: WitnessValueConvention { result.convention }
    package var returnDependency: WitnessValueDependency {
        result.dependency.legacyProjection
    }
    package var argumentLayouts: [ABIClass] { arguments.map(\.value.layout) }
    package var returnLayout: ABIClass { result.layout }
    package var typedErrorType: Any.Type? { effects.throwing.typedError?.type }
    package var typedErrorLayout: ABIClass? { effects.throwing.typedError?.layout }
    package var typedErrorDependency: WitnessValueDependency {
        effects.throwing.typedError?.dependency.legacyProjection ?? .independent
    }
    package var typedErrorUsesIndirectResultSlot: Bool {
        effects.throwing.typedError?.usesIndirectResultSlot ?? false
    }
    package var isThrowing: Bool { effects.throwing.isThrowing }
    package var isAsync: Bool { effects.isAsync }
    package var hasReliableThrowing: Bool { effects.throwing.isReliable }

    /// The ABI-free projection consumed by the public semantic layer.
    package var runtimeMethod: RuntimeMethod {
        RuntimeMethod(
            kind: RuntimeRequirementKind(kind),
            receiver: RuntimeRequirementReceiver(receiver),
            origin: RuntimeRequirementOrigin(origin),
            name: name,
            slot: index,
            witnessSlot: witnessIndex,
            arguments: arguments.map { argument in
                RuntimeArgument(
                    value: RuntimeValue(
                        type: argument.value.type,
                        convention: RuntimeValueConvention(argument.value.convention),
                        dependency: RuntimeValueDependency(argument.value.dependency)
                    ),
                    ownership: RuntimeArgumentOwnership(argument.ownership)
                )
            },
            result: RuntimeValue(
                type: result.type,
                convention: RuntimeValueConvention(result.convention),
                dependency: RuntimeValueDependency(result.dependency)
            ),
            typedErrorType: typedErrorType,
            typedErrorDependency: effects.throwing.typedError.map {
                RuntimeValueDependency($0.dependency)
            },
            selfIsClassConstrained: selfIsClassConstrained,
            isThrowing: isThrowing,
            isAsync: isAsync,
            hasReliableThrowing: hasReliableThrowing
        )
    }

    package var signatureDescription: String {
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

    package func hasSameSignature(as discovered: Self) -> Bool {
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
        dependency: WitnessValueDependency,
        selfIsClassConstrained: Bool
    ) -> ABIClass {
        if dependency.usesOpaqueValueWitnessConvention {
            return .indirect
        }
        return switch convention {
            case .concrete: abiClass(for: type)
            case .associatedType: .indirect
            case .selfType, .optionalSelf:
                selfIsClassConstrained ? .integer(words: 1) : .indirect
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

extension RuntimeRequirementKind {
    fileprivate init(_ kind: StubRequirementKind) {
        switch kind {
            case .method: self = .method
            case .initializer: self = .initializer
            case .getter: self = .getter
            case .setter: self = .setter
        }
    }
}

extension RuntimeRequirementReceiver {
    fileprivate init(_ receiver: StubRequirementReceiver) {
        switch receiver {
            case .instance: self = .instance
            case .metatype: self = .metatype
        }
    }
}

extension RuntimeRequirementOrigin {
    fileprivate init(_ origin: MethodDescriptor.Origin) {
        switch origin {
            case .automatic: self = .automatic
            case .explicit: self = .explicit
            case .manual: self = .manual
        }
    }
}

extension RuntimeValueConvention {
    fileprivate init(_ convention: WitnessValueConvention) {
        switch convention {
            case .concrete: self = .concrete
            case .associatedType(let name): self = .associatedType(name: name)
            case .selfType: self = .selfType
            case .optionalSelf: self = .optionalSelf
        }
    }
}

extension RuntimeArgumentOwnership {
    fileprivate init(_ ownership: WitnessArgumentOwnership) {
        switch ownership {
            case .borrowed: self = .borrowed
            case .owned: self = .owned
        }
    }
}

extension RuntimeValueDependency {
    fileprivate init(_ dependency: WitnessValueDependency) {
        switch dependency {
            case .independent:
                self = .independent
            case .associatedType(let reference):
                self =
                    reference.usesReferenceABI
                    ? .referenceAssociatedType(name: reference.name)
                    : .associatedType(name: reference.name)
            case .optional(let wrapped):
                self = .optional(Self(wrapped))
            case .array(let element):
                self = .array(Self(element))
            case .set(let element):
                self = .set(Self(element))
            case .dictionary(let key, let value):
                self = .dictionary(key: Self(key), value: Self(value))
            case .result(let success, let failure):
                self = .result(success: Self(success), failure: Self(failure))
            case .genericClass(let constructor, let arguments):
                self = .genericClass(
                    name: constructor.name,
                    arguments: arguments.map(Self.init)
                )
        }
    }
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

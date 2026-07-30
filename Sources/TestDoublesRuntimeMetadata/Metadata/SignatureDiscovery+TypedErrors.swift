import Echo

func resolveTypedError(
    _ syntax: DemangledTypeSyntax?,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings
) throws -> (type: Any.Type, dependency: WitnessValueDependency)? {
    guard let syntax else { return nil }
    let name = syntax.canonicalSpelling
    if let associatedTypeName = directAssociatedTypeName(
        in: name,
        protocolDescriptor: protocolDescriptor,
        associatedTypeBindings: associatedTypeBindings
    ) {
        let binding = try associatedTypeBindings.binding(
            named: associatedTypeName,
            declaredBy: protocolDescriptor
        )
        guard binding.type is any Error.Type else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Associated typed error '\(associatedTypeName)' is bound to '\(runtimeTypeName(binding.type))', which does not conform to Error."
            )
        }
        return (
            binding.type,
            associatedTypeBindings.dependency(for: binding)
        )
    }
    if let resolved = try resolveSupportedAssociatedTypedErrorNominal(
        name,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings
    ) {
        guard resolved.type is any Error.Type else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Associated-dependent typed error '\(name)' resolves to '\(runtimeTypeName(resolved.type))', which does not conform to Error."
            )
        }
        return (resolved.type, resolved.dependency)
    }
    if referencesAssociatedType(
        in: name,
        protocolDescriptor: protocolDescriptor,
        associatedTypeBindings: associatedTypeBindings
    ) {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds an associated type inside unsupported typed error '\(name)'. "
                + "Only a direct associated typed error or a linked, top-level generic class with one or two type parameters is supported."
        )
    }
    guard let type = resolveRuntimeType(syntax) else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has typed error '\(name)' whose runtime metadata could not be resolved."
        )
    }
    guard reflect(type).kind != .function else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has a function-valued typed error."
        )
    }
    return (type, .independent)
}

private func resolveSupportedAssociatedTypedErrorNominal(
    _ spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings
) throws -> ResolvedDependentType? {
    guard
        referencesAssociatedType(
            in: spelling,
            protocolDescriptor: protocolDescriptor,
            associatedTypeBindings: associatedTypeBindings
        ), genericApplication(spelling) != nil
    else {
        return nil
    }
    let resolved = try resolveAssociatedTypedErrorNominalComponent(
        spelling,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings
    )
    return resolved.dependency.isAssociatedTypeDependent ? resolved : nil
}

private func resolveAssociatedTypedErrorNominalComponent(
    _ spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings
) throws -> ResolvedDependentType {
    if let name = directAssociatedTypeName(
        in: spelling,
        protocolDescriptor: protocolDescriptor,
        associatedTypeBindings: associatedTypeBindings
    ) {
        return try associatedTypeBindings.resolvedAssociatedType(
            named: name,
            declaredBy: protocolDescriptor
        )
    }
    if let application = genericApplication(spelling),
        let argumentSpellings = topLevelComponents(in: application.arguments)
    {
        guard argumentSpellings.count <= 2 else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds an associated type inside unsupported typed error '\(spelling)'. "
                    + "Associated-dependent typed errors currently support generic nominals with at most two type parameters."
            )
        }
        let arguments = try argumentSpellings.map {
            try resolveAssociatedTypedErrorNominalComponent(
                $0,
                protocolDescriptor: protocolDescriptor,
                requirementIndex: requirementIndex,
                associatedTypeBindings: associatedTypeBindings
            )
        }
        if let resolved = genericClassType(
            named: application.constructor,
            arguments: arguments.map(\.type)
        ) {
            return ResolvedDependentType(
                type: resolved.type,
                dependency: .genericClass(
                    constructor: resolved.constructor,
                    arguments: arguments.map(\.dependency)
                )
            )
        }
        if let resolved = genericValueType(
            named: application.constructor,
            arguments: arguments.map(\.type)
        ) {
            return ResolvedDependentType(
                type: resolved.type,
                dependency: .genericValue(
                    constructor: resolved.constructor,
                    arguments: arguments.map(\.dependency)
                )
            )
        }
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds an associated type inside unsupported typed error '\(spelling)'. "
                + "Only a direct associated typed error or a linked, top-level generic class, struct, or enum with one or two type parameters is supported. "
                + "Optional and other unproven value wrappers, and source-less constructors remain unsupported."
        )
    }
    if referencesAssociatedType(
        in: spelling,
        protocolDescriptor: protocolDescriptor,
        associatedTypeBindings: associatedTypeBindings
    ) {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds an associated type inside unsupported typed-error component '\(spelling)'. "
                + "Only direct associated-type arguments and nested linked generic nominals are supported."
        )
    }
    guard let syntax = DemangledTypeSyntax(spelling),
        let type = resolveRuntimeType(syntax)
    else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has typed-error component '\(spelling)' whose runtime metadata could not be resolved."
        )
    }
    return ResolvedDependentType(type: type, dependency: .independent)
}

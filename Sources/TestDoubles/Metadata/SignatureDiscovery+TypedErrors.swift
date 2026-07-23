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
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Associated typed error '\(associatedTypeName)' is bound to '\(runtimeTypeName(binding.type))', which does not conform to Error."
            )
        }
        return (
            binding.type,
            associatedTypeBindings.dependency(for: binding)
        )
    }
    if let resolved = try resolveSupportedAssociatedTypedErrorClass(
        name,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings
    ) {
        guard resolved.type is any Error.Type else {
            throw StubError.unsupportedProtocolShape(
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
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds an associated type inside unsupported typed error '\(name)'. "
                + "Only a direct associated typed error or a linked, top-level generic class with one or two unconstrained type parameters is supported."
        )
    }
    guard let type = resolveRuntimeType(syntax) else {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has typed error '\(name)' whose runtime metadata could not be resolved."
        )
    }
    guard reflect(type).kind != .function else {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has a function-valued typed error."
        )
    }
    return (type, .independent)
}

private func resolveSupportedAssociatedTypedErrorClass(
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
    let resolved = try resolveAssociatedTypedErrorClassComponent(
        spelling,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings
    )
    return resolved.dependency.isAssociatedTypeDependent ? resolved : nil
}

private func resolveAssociatedTypedErrorClassComponent(
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
        let arguments = try argumentSpellings.map {
            try resolveAssociatedTypedErrorClassComponent(
                $0,
                protocolDescriptor: protocolDescriptor,
                requirementIndex: requirementIndex,
                associatedTypeBindings: associatedTypeBindings
            )
        }
        guard
            let resolved = genericClassType(
                named: application.constructor,
                arguments: arguments.map(\.type)
            )
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds an associated type inside unsupported typed error '\(spelling)'. "
                    + "Only a direct associated typed error or a linked, top-level generic class with one or two unconstrained type parameters is supported. "
                    + "Optional and other value wrappers, generic structs or enums, constrained classes, and source-less constructors remain unsupported."
            )
        }
        return ResolvedDependentType(
            type: resolved.type,
            dependency: .genericClass(
                constructor: resolved.constructor,
                arguments: arguments.map(\.dependency)
            )
        )
    }
    if referencesAssociatedType(
        in: spelling,
        protocolDescriptor: protocolDescriptor,
        associatedTypeBindings: associatedTypeBindings
    ) {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds an associated type inside unsupported typed-error component '\(spelling)'. "
                + "Only direct associated-type arguments and nested linked generic classes are supported."
        )
    }
    guard let syntax = DemangledTypeSyntax(spelling),
        let type = resolveRuntimeType(syntax)
    else {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) has typed-error component '\(spelling)' whose runtime metadata could not be resolved."
        )
    }
    return ResolvedDependentType(type: type, dependency: .independent)
}

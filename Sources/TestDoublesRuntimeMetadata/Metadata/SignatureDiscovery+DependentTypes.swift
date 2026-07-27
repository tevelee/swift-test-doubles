import Echo

func resolveSupportedDependentType(
    _ spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings,
    mangledSignature: String
) throws -> ResolvedDependentType? {
    guard
        referencesAssociatedType(
            in: spelling,
            protocolDescriptor: protocolDescriptor,
            associatedTypeBindings: associatedTypeBindings
        ),
        directAssociatedTypeName(
            in: spelling,
            protocolDescriptor: protocolDescriptor,
            associatedTypeBindings: associatedTypeBindings
        ) != nil || standardLibraryDependentShape(in: spelling) != nil
            || genericApplication(spelling) != nil
    else {
        return nil
    }
    let resolved = try resolveSupportedTypeComponent(
        spelling,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings,
        mangledSignature: mangledSignature
    )
    return resolved.dependency.isAssociatedTypeDependent ? resolved : nil
}

// Only the verbose "Dictionary<K, V>" form is handled: the exported
// swift_demangle C function this codebase calls always runs with
// SynthesizeSugarOnTypes = false, unlike the swift-demangle CLI, so it
// never emits "[K: V]" sugar.
private func dictionaryComponents(in name: String) -> (key: String, value: String)? {
    for constructor in ["Dictionary", "Swift.Dictionary"] {
        let prefix = "\(constructor)<"
        guard name.hasPrefix(prefix), name.last == ">" else { continue }
        let arguments = String(name.dropFirst(prefix.count).dropLast())
        guard let components = topLevelComponents(in: arguments), components.count == 2
        else {
            return nil
        }
        return (components[0], components[1])
    }
    return nil
}

private func resolveSupportedTypeComponent(
    _ spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings,
    mangledSignature: String
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
    if let shape = standardLibraryDependentShape(in: spelling) {
        switch shape {
            case .optional(let wrapped):
                return try resolveSupportedTypeComponent(
                    wrapped,
                    protocolDescriptor: protocolDescriptor,
                    requirementIndex: requirementIndex,
                    associatedTypeBindings: associatedTypeBindings,
                    mangledSignature: mangledSignature
                ).optional()
            case .array(let element):
                return try resolveSupportedTypeComponent(
                    element,
                    protocolDescriptor: protocolDescriptor,
                    requirementIndex: requirementIndex,
                    associatedTypeBindings: associatedTypeBindings,
                    mangledSignature: mangledSignature
                ).array()
            case .set(let element):
                return try resolveSupportedTypeComponent(
                    element,
                    protocolDescriptor: protocolDescriptor,
                    requirementIndex: requirementIndex,
                    associatedTypeBindings: associatedTypeBindings,
                    mangledSignature: mangledSignature
                ).set(
                    protocolName: protocolDescriptor.name,
                    sourceDescription: element
                )
            case .dictionary(let key, let value):
                return try .dictionary(
                    key: resolveSupportedTypeComponent(
                        key,
                        protocolDescriptor: protocolDescriptor,
                        requirementIndex: requirementIndex,
                        associatedTypeBindings: associatedTypeBindings,
                        mangledSignature: mangledSignature
                    ),
                    value: resolveSupportedTypeComponent(
                        value,
                        protocolDescriptor: protocolDescriptor,
                        requirementIndex: requirementIndex,
                        associatedTypeBindings: associatedTypeBindings,
                        mangledSignature: mangledSignature
                    ),
                    protocolName: protocolDescriptor.name
                )
            case .result(let success, let failure):
                return try .result(
                    success: resolveSupportedTypeComponent(
                        success,
                        protocolDescriptor: protocolDescriptor,
                        requirementIndex: requirementIndex,
                        associatedTypeBindings: associatedTypeBindings,
                        mangledSignature: mangledSignature
                    ),
                    failure: resolveSupportedTypeComponent(
                        failure,
                        protocolDescriptor: protocolDescriptor,
                        requirementIndex: requirementIndex,
                        associatedTypeBindings: associatedTypeBindings,
                        mangledSignature: mangledSignature
                    ),
                    protocolName: protocolDescriptor.name
                )
        }
    }
    if let application = genericApplication(spelling),
        let argumentSpellings = topLevelComponents(
            in: application.arguments
        )
    {
        let arguments = try argumentSpellings.map {
            try resolveSupportedTypeComponent(
                $0,
                protocolDescriptor: protocolDescriptor,
                requirementIndex: requirementIndex,
                associatedTypeBindings: associatedTypeBindings,
                mangledSignature: mangledSignature
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
                "Requirement \(requirementIndex) embeds an associated type inside unsupported generic nominal '\(spelling)'. "
                + "Only linked, top-level generic classes, structs, and enums with one or two type parameters are supported."
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
                "Requirement \(requirementIndex) embeds an associated type inside unsupported type '\(spelling)'. "
                + "Bound associated-type support accepts recursive combinations of Optional, Array, Set, Dictionary, Result, "
                + "and linked generic classes, structs, and enums with one or two type parameters."
        )
    }
    guard let syntax = DemangledTypeSyntax(spelling),
        let type = resolveRuntimeType(
            syntax,
            containedInMangledSymbol: mangledSignature
        )
    else {
        throw RuntimeConstructionError.signatureDiscoveryFailed(
            protocolName: protocolDescriptor.name,
            requirementIndex: requirementIndex,
            details: "Could not resolve runtime metadata for nested generic argument '\(spelling)'. Supply explicit Requirement values."
        )
    }
    return ResolvedDependentType(type: type, dependency: .independent)
}

private enum StandardLibraryDependentShape {
    case optional(String)
    case array(String)
    case set(String)
    case dictionary(key: String, value: String)
    case result(success: String, failure: String)
}

private func standardLibraryDependentShape(
    in spelling: String
) -> StandardLibraryDependentShape? {
    if let wrapped = unaryGenericArgument(
        in: spelling,
        constructors: ["Optional", "Swift.Optional"]
    ) {
        return .optional(wrapped)
    }
    if let components = dictionaryComponents(in: spelling) {
        return .dictionary(key: components.key, value: components.value)
    }
    if let components = binaryGenericArguments(
        in: spelling,
        constructors: ["Result", "Swift.Result"]
    ) {
        return .result(
            success: components.first,
            failure: components.second
        )
    }
    if let element = unaryGenericArgument(
        in: spelling,
        constructors: ["Array", "Swift.Array"]
    ) {
        return .array(element)
    }
    if let element = unaryGenericArgument(
        in: spelling,
        constructors: ["Set", "Swift.Set"]
    ) {
        return .set(element)
    }
    return nil
}

private func binaryGenericArguments(
    in spelling: String,
    constructors: [String]
) -> (first: String, second: String)? {
    for constructor in constructors {
        let prefix = "\(constructor)<"
        guard spelling.hasPrefix(prefix), spelling.last == ">" else { continue }
        let arguments = String(spelling.dropFirst(prefix.count).dropLast())
        guard let components = topLevelComponents(in: arguments),
            components.count == 2
        else {
            return nil
        }
        return (components[0], components[1])
    }
    return nil
}

private func unaryGenericArgument(
    in spelling: String,
    constructors: [String]
) -> String? {
    for constructor in constructors {
        let prefix = "\(constructor)<"
        guard spelling.hasPrefix(prefix), spelling.last == ">" else { continue }
        let arguments = String(spelling.dropFirst(prefix.count).dropLast())
        guard let components = topLevelComponents(in: arguments),
            components.count == 1
        else {
            return nil
        }
        return components[0]
    }
    return nil
}

func directAssociatedTypeName(
    in spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    associatedTypeBindings: AssociatedTypeBindings
) -> String? {
    associatedTypeBindings.declared(by: protocolDescriptor).first { binding in
        spelling == "A.\(binding.name)" || spelling == "Self.\(binding.name)"
    }?.name
}

func referencesAssociatedType(
    in spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    associatedTypeBindings: AssociatedTypeBindings
) -> Bool {
    associatedTypeBindings.declared(by: protocolDescriptor).contains { binding in
        spelling.contains("A.\(binding.name)")
            || spelling.contains("Self.\(binding.name)")
    }
}

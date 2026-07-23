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

private func dictionaryComponents(in name: String) -> (key: String, value: String)? {
    if name.first == "[", name.last == "]" {
        let contents = String(name.dropFirst().dropLast())
        guard let colon = lastTopLevelColon(in: contents) else { return nil }
        return (
            String(contents[..<colon]).trimmingCharacters(in: .whitespaces),
            String(contents[contents.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        )
    }
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
        guard
            let resolved = genericClassType(
                named: application.constructor,
                arguments: arguments.map(\.type)
            )
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds an associated type inside unsupported generic nominal '\(spelling)'. "
                    + "Only linked, top-level generic classes with one or two unconstrained type parameters are supported. "
                    + "Generic structs, enums, constrained classes, and other constructors remain unsupported."
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
                "Requirement \(requirementIndex) embeds an associated type inside unsupported type '\(spelling)'. "
                + "Bound associated-type support accepts recursive combinations of Optional, Array, Set, Dictionary, Result, "
                + "and linked generic classes with one or two unconstrained type parameters."
        )
    }
    guard let syntax = DemangledTypeSyntax(spelling),
        let type = resolveRuntimeType(
            syntax,
            containedInMangledSymbol: mangledSignature
        )
    else {
        throw StubError.signatureDiscoveryFailed(
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
    if spelling.hasSuffix("?") {
        return .optional(String(spelling.dropLast()))
    }
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
    if spelling.first == "[", spelling.last == "]" {
        return .array(String(spelling.dropFirst().dropLast()))
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

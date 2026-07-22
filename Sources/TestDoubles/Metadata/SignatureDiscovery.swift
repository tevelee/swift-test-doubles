import CTestDoublesTrampoline
import Echo
import Foundation

enum GetterEffectDiscoveryPolicy {
    /// Preserves automatic discovery's historical behavior: synchronous
    /// getters are accepted with an unreliable nonthrowing placeholder, while
    /// async getters require an explicit source of truth.
    case automatic
    /// Supplies the effect that Swift's protocol metadata and witness symbols
    /// omit. The caller validates that every getter has exactly one entry.
    case hints([ProtocolLayout.GetterRequirementID: Bool])
    /// Explicit requirements are authoritative for getter effects. Linked
    /// discovery still validates every signature component it can observe.
    case explicitRequirementValidation
}

/// Discovers method signatures using symbol lookup and demangling. Linked
/// witness thunks are preferred; resilient protocols can fall back to their
/// exported per-requirement method descriptor symbols.
func discoverMethods(
    witnessTables: [ProtocolLayout.DescriptorID: WitnessTable],
    layout: ProtocolLayout,
    requirements: [ProtocolLayout.CallableRequirement]? = nil,
    associatedTypeBindings: AssociatedTypeBindings = AssociatedTypeBindings(),
    getterEffectPolicy: GetterEffectDiscoveryPolicy = .automatic
) throws -> [MethodDescriptor] {
    var results = [MethodDescriptor]()

    for requirement in requirements ?? layout.callableRequirements {
        let proto = requirement.protocolDescriptor
        let requirementIndex = requirement.witnessIndex
        let req = proto.requirements[requirementIndex]
        let symbols = requirementSymbolNames(
            requirement,
            witnessTables: witnessTables
        )
        guard symbols.names.isEmpty == false else {
            if symbols.hasWitnessTable {
                throw StubError.signatureDiscoveryFailed(
                    protocolName: proto.name,
                    requirementIndex: requirement.dispatchIndex,
                    details: "Neither the witness entry nor the protocol requirement descriptor has a resolvable signature symbol. Supply explicit Requirement values."
                )
            }
            throw StubError.noConformanceFound(protocolName: proto.name)
        }

        var attempted: [String] = []
        var parsed: ParsedWitnessSignature?
        var parsedMangledName: String?
        for mangledName in symbols.names {
            let demangled = RuntimeSymbols.demangle(mangledName)
            attempted.append(demangled)
            if let candidate = parseWitnessSignature(demangled, kind: req.flags.kind) {
                parsed = candidate
                parsedMangledName = mangledName
                break
            }
        }
        guard let parsed, let parsedMangledName else {
            throw StubError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: requirement.dispatchIndex,
                details: "Could not parse any discovered symbol: \(attempted.joined(separator: "; ")). Supply explicit Requirement values."
            )
        }
        let kind = requirement.kind
        // Swift 6.3 read-coroutine flags reuse bit 0x20 as part of the
        // requirement kind, so it is not the ordinary async marker here.
        let isAsync = req.flags.kind == .readCoroutine ? false : req.flags.isAsync
        let getterEffect: (isThrowing: Bool, isReliable: Bool)? =
            if kind == .getter {
                try resolveGetterEffect(
                    policy: getterEffectPolicy,
                    protocolDescriptor: proto,
                    witnessIndex: requirementIndex,
                    dispatchIndex: requirement.dispatchIndex,
                    isAsync: isAsync
                )
            } else {
                nil
            }
        let arguments = try parsed.argumentTypes.map { type in
            try resolveWitnessValue(
                type,
                protocolDescriptor: proto,
                requirementIndex: requirement.dispatchIndex,
                associatedTypeBindings: associatedTypeBindings,
                mangledSignature: parsedMangledName
            )
        }
        let result = try resolveWitnessValue(
            parsed.returnType,
            protocolDescriptor: proto,
            requirementIndex: requirement.dispatchIndex,
            associatedTypeBindings: associatedTypeBindings,
            mangledSignature: parsedMangledName
        )

        let typedError = try resolveTypedError(
            parsed.typedError,
            protocolDescriptor: proto,
            requirementIndex: requirement.dispatchIndex,
            associatedTypeBindings: associatedTypeBindings
        )
        if typedError != nil {
            let supportsResultConvention =
                switch result.convention {
                    case .concrete, .associatedType:
                        true
                    case .selfType, .optionalSelf:
                        false
                }
            guard kind == .method,
                supportsResultConvention
            else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: proto.name,
                    reason: "Requirement \(requirement.dispatchIndex) combines typed throws with an unsupported accessor, initializer, or Self result convention."
                )
            }
        }

        results.append(
            try MethodDescriptor(
                kind: kind,
                receiver: requirement.receiver,
                name: parsed.name,
                index: requirement.dispatchIndex,
                witnessIndex: requirementIndex,
                arguments: arguments,
                result: result,
                protocolName: proto.name,
                typedErrorType: typedError?.type,
                typedErrorDependency: typedError?.dependency ?? .independent,
                selfIsClassConstrained: protocolUsesClassSelfConvention(proto),
                isThrowing: getterEffect?.isThrowing ?? parsed.isThrowing,
                isAsync: isAsync,
                hasReliableThrowing: getterEffect?.isReliable ?? true
            ))
    }

    return results
}

private func requirementSymbolNames(
    _ requirement: ProtocolLayout.CallableRequirement,
    witnessTables: [ProtocolLayout.DescriptorID: WitnessTable]
) -> (names: [String], hasWitnessTable: Bool) {
    let proto = requirement.protocolDescriptor
    let requirementIndex = requirement.witnessIndex
    var names: [String] = []
    if let witnessTable = witnessTables[ProtocolLayout.DescriptorID(proto)] {
        let wordSize = MemoryLayout<UnsafeRawPointer>.size
        let function = (witnessTable.ptr + (1 + requirementIndex) * wordSize)
            .load(as: UnsafeRawPointer.self)
        if let symbol = td_symbol_name(function) {
            names.append(String(cString: symbol))
        }
    }

    if let descriptorName = resilientRequirementSymbolName(requirement),
        names.contains(descriptorName) == false
    {
        names.append(descriptorName)
    }
    return (
        names,
        witnessTables[ProtocolLayout.DescriptorID(proto)] != nil
    )
}

func resilientRequirementSymbolName(
    _ requirement: ProtocolLayout.CallableRequirement
) -> String? {
    let proto = requirement.protocolDescriptor
    let descriptor = protocolRequirementDescriptor(
        protocolDescriptor: proto,
        requirementIndex: requirement.witnessIndex
    )
    guard let symbol = td_exact_symbol_name(descriptor) else { return nil }
    let name = String(cString: symbol)
    return name.hasSuffix("Tq") ? name : nil
}

/// The stable ABI records are six, three, and two 32-bit words respectively:
/// the fixed protocol descriptor, each generic requirement, and each protocol
/// requirement. Resilient protocols export a `Tq` symbol at the final address.
private func protocolRequirementDescriptor(
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int
) -> UnsafeRawPointer {
    let word32 = MemoryLayout<UInt32>.size
    let protocolDescriptorSize = 6 * word32
    let genericRequirementSize = 3 * word32
    let protocolRequirementSize = 2 * word32
    return protocolDescriptor.ptr
        + protocolDescriptorSize
        + protocolDescriptor.numRequirementsInSignature * genericRequirementSize
        + requirementIndex * protocolRequirementSize
}

private func resolveGetterEffect(
    policy: GetterEffectDiscoveryPolicy,
    protocolDescriptor: ProtocolDescriptor,
    witnessIndex: Int,
    dispatchIndex: Int,
    isAsync: Bool
) throws -> (isThrowing: Bool, isReliable: Bool) {
    switch policy {
        case .automatic:
            guard isAsync == false else {
                throw StubError.signatureDiscoveryFailed(
                    protocolName: protocolDescriptor.name,
                    requirementIndex: dispatchIndex,
                    details: "Swift witness symbols do not encode whether an async getter throws. Supply GetterEffect hints or explicit Requirement values for effectful getters."
                )
            }
            return (false, false)

        case .hints(let hints):
            let identifier = ProtocolLayout.GetterRequirementID(
                protocolDescriptor: protocolDescriptor,
                witnessIndex: witnessIndex
            )
            guard let isThrowing = hints[identifier] else {
                throw StubError.signatureDiscoveryFailed(
                    protocolName: protocolDescriptor.name,
                    requirementIndex: dispatchIndex,
                    details: "No GetterEffect hint was supplied for this getter."
                )
            }
            return (isThrowing, true)

        case .explicitRequirementValidation:
            return (false, false)
    }
}

private func resolveWitnessValue(
    _ syntax: DemangledTypeSyntax,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int,
    associatedTypeBindings: AssociatedTypeBindings,
    mangledSignature: String
) throws -> ResolvedWitnessValue {
    let rawName = syntax.canonicalSpelling
    if rawName.hasPrefix("inout ") {
        let valueName = String(rawName.dropFirst("inout ".count))
        if dynamicSelfValueShape(valueName) != nil
            || containsDynamicSelfReference(valueName)
        {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) uses an inout Self argument. "
                    + "Automatic Stub supports only borrowed/default and consuming direct or single-Optional Self arguments."
            )
        }
    }

    var valueName = rawName
    let isAutoclosure = valueName.hasPrefix("@autoclosure ")
    if isAutoclosure {
        valueName.removeFirst("@autoclosure ".count)
    }
    let ownership: WitnessArgumentOwnership?
    if valueName.hasPrefix("__owned ") {
        valueName.removeFirst("__owned ".count)
        ownership = .owned
    } else if valueName.hasPrefix("consuming ") {
        valueName.removeFirst("consuming ".count)
        ownership = .owned
    } else if valueName.hasPrefix("borrowing ") {
        valueName.removeFirst("borrowing ".count)
        ownership = .borrowed
    } else if valueName.hasPrefix("__shared ") {
        valueName.removeFirst("__shared ".count)
        ownership = .borrowed
    } else {
        ownership = nil
    }
    if let selfShape = dynamicSelfValueShape(valueName) {
        guard isAutoclosure == false else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) uses Self through an autoclosure argument. "
                    + "Automatic Stub supports only direct Self and one Optional layer."
            )
        }
        return .selfValue(
            isOptional: selfShape == .optional,
            ownership: ownership
        )
    }
    if containsDynamicSelfReference(valueName) {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds Self inside unsupported type '\(valueName)'. "
                + "Automatic Stub supports only direct Self and one Optional layer."
        )
    }

    let bindings = associatedTypeBindings.declared(by: protocolDescriptor)
    if case .function(let function)? = DemangledTypeSyntax(valueName),
        referencesAssociatedType(
            in: function.canonicalSpelling,
            protocolDescriptor: protocolDescriptor,
            associatedTypeBindings: associatedTypeBindings
        )
    {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) uses an associated-dependent function value. "
                + "Its fixed two-word outer layout does not determine the inner generic calling convention. "
                + "Automatic and explicit construction fail closed before transport."
        )
    }
    for binding in bindings {
        let spellings = ["A.\(binding.name)", "Self.\(binding.name)"]
        if spellings.contains(valueName) {
            continue
        }
        if let spelling = spellings.first(where: { rawName.hasSuffix(" \($0)") }) {
            let ownership = rawName.dropLast(spelling.count).trimmingCharacters(in: .whitespaces)
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(requirementIndex) uses unsupported ownership spelling '\(ownership)' for associated type '\(binding.name)'. Only borrowed and __owned associated-type arguments are supported."
            )
        }
    }

    if let dependentType = try resolveSupportedDependentType(
        valueName,
        protocolDescriptor: protocolDescriptor,
        requirementIndex: requirementIndex,
        associatedTypeBindings: associatedTypeBindings,
        mangledSignature: mangledSignature
    ) {
        return .resolved(dependentType, ownership: ownership)
    }

    for binding in bindings {
        let spellings = ["A.\(binding.name)", "Self.\(binding.name)"]
        if spellings.contains(where: valueName.contains) {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds associated type '\(binding.name)' inside unsupported type '\(valueName)'. "
                    + "Bound associated-type support accepts recursive combinations of Optional, Array, Set, Dictionary, Result, and linked generic classes with one or two unconstrained type parameters."
            )
        }
    }
    guard let concreteSyntax = DemangledTypeSyntax(valueName),
        let type = resolveRuntimeType(
            concreteSyntax,
            containedInMangledSymbol: mangledSignature
        )
    else {
        throw StubError.signatureDiscoveryFailed(
            protocolName: protocolDescriptor.name,
            requirementIndex: requirementIndex,
            details: "Could not resolve runtime metadata for type '\(rawName)'. Supply explicit Requirement values."
        )
    }
    return ResolvedWitnessValue(
        type: type,
        convention: .concrete,
        dependency: .independent,
        ownership: ownership
    )
}

private enum DynamicSelfValueShape {
    case direct, optional
}

private func dynamicSelfValueShape(
    _ spelling: String
) -> DynamicSelfValueShape? {
    switch spelling {
        case "A", "Self":
            .direct
        case "A?", "Self?", "Optional<A>", "Swift.Optional<A>",
            "Optional<Self>", "Swift.Optional<Self>":
            .optional
        default:
            nil
    }
}

private func containsDynamicSelfReference(_ spelling: String) -> Bool {
    let bytes = Array(spelling.utf8)
    func isIdentifierByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5a)
            || (byte >= 0x61 && byte <= 0x7a)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x5f
            || byte == 0x2e
    }
    func endsToken(at index: Int) -> Bool {
        index == bytes.count || isIdentifierByte(bytes[index]) == false
    }
    for index in bytes.indices {
        if index > 0 && isIdentifierByte(bytes[index - 1]) { continue }
        if bytes[index] == 0x41 && endsToken(at: index + 1) {
            return true
        }
        if index + 4 <= bytes.count,
            bytes[index ..< index + 4].elementsEqual([0x53, 0x65, 0x6c, 0x66]),
            endsToken(at: index + 4)
        {
            return true
        }
    }
    return false
}

private func resolveTypedError(
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

private func resolveSupportedDependentType(
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

private func directAssociatedTypeName(
    in spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    associatedTypeBindings: AssociatedTypeBindings
) -> String? {
    associatedTypeBindings.declared(by: protocolDescriptor).first { binding in
        spelling == "A.\(binding.name)" || spelling == "Self.\(binding.name)"
    }?.name
}

private func referencesAssociatedType(
    in spelling: String,
    protocolDescriptor: ProtocolDescriptor,
    associatedTypeBindings: AssociatedTypeBindings
) -> Bool {
    associatedTypeBindings.declared(by: protocolDescriptor).contains { binding in
        spelling.contains("A.\(binding.name)")
            || spelling.contains("Self.\(binding.name)")
    }
}

extension ProtocolRequirement.Flags {
    var isAsync: Bool { bits & 0x20 != 0 }
}

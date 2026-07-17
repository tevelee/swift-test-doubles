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
    selfIsClassConstrained: Bool = false,
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
        let isAsync = req.flags.isAsync
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

        let typedErrorType = try resolveTypedErrorType(
            parsed.typedError,
            protocolDescriptor: proto,
            requirementIndex: requirement.dispatchIndex
        )
        if typedErrorType != nil {
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
                typedErrorType: typedErrorType,
                selfIsClassConstrained: selfIsClassConstrained,
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
    let name = syntax.canonicalSpelling
    switch name {
        case "A", "Self":
            return .selfValue(isOptional: false)
        case "A?", "Self?", "Optional<A>", "Swift.Optional<A>",
            "Optional<Self>", "Swift.Optional<Self>":
            return .selfValue(isOptional: true)
        default:
            break
    }

    let bindings = associatedTypeBindings.declared(by: protocolDescriptor)
    for binding in bindings {
        let spellings = ["A.\(binding.name)", "Self.\(binding.name)"]
        let valueName: String
        let ownership: WitnessArgumentOwnership?
        if name.hasPrefix("__owned ") {
            valueName = String(name.dropFirst("__owned ".count))
            ownership = .owned
        } else {
            valueName = name
            ownership = nil
        }
        if spellings.contains(valueName) {
            return .associatedType(binding: binding, ownership: ownership)
        }
        if let container = associatedTypeContainer(in: valueName, spellings: spellings) {
            return try .associatedType(
                binding: binding,
                container: container,
                ownership: ownership
            )
        }
    }

    for binding in bindings {
        let spellings = ["A.\(binding.name)", "Self.\(binding.name)"]
        if let spelling = spellings.first(where: { name.hasSuffix(" \($0)") }) {
            let ownership = name.dropLast(spelling.count).trimmingCharacters(in: .whitespaces)
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(requirementIndex) uses unsupported ownership spelling '\(ownership)' for associated type '\(binding.name)'. Only borrowed and __owned associated-type arguments are supported."
            )
        }
        if spellings.contains(where: name.contains) {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(requirementIndex) embeds associated type '\(binding.name)' inside unsupported type '\(name)'. Bound associated-type support accepts direct, Optional, Array, and Set occurrences."
            )
        }
    }
    var concreteName = name
    let concreteOwnership: WitnessArgumentOwnership?
    if concreteName.hasPrefix("@autoclosure ") {
        concreteName.removeFirst("@autoclosure ".count)
    }
    if concreteName.hasPrefix("__owned ") {
        concreteName.removeFirst("__owned ".count)
        concreteOwnership = .owned
    } else if concreteName.hasPrefix("consuming ") {
        concreteName.removeFirst("consuming ".count)
        concreteOwnership = .owned
    } else if concreteName.hasPrefix("borrowing ") {
        concreteName.removeFirst("borrowing ".count)
        concreteOwnership = .borrowed
    } else if concreteName.hasPrefix("__shared ") {
        concreteName.removeFirst("__shared ".count)
        concreteOwnership = .borrowed
    } else {
        concreteOwnership = nil
    }
    guard let concreteSyntax = DemangledTypeSyntax(concreteName),
        let type = resolveRuntimeType(
            concreteSyntax,
            containedInMangledSymbol: mangledSignature
        )
    else {
        throw StubError.signatureDiscoveryFailed(
            protocolName: protocolDescriptor.name,
            requirementIndex: requirementIndex,
            details: "Could not resolve runtime metadata for type '\(name)'. Supply explicit Requirement values."
        )
    }
    return ResolvedWitnessValue(
        type: type,
        convention: .concrete,
        dependency: .independent,
        ownership: concreteOwnership
    )
}

private func resolveTypedErrorType(
    _ syntax: DemangledTypeSyntax?,
    protocolDescriptor: ProtocolDescriptor,
    requirementIndex: Int
) throws -> Any.Type? {
    guard let syntax else { return nil }
    let name = syntax.canonicalSpelling
    guard name.contains("A.") == false,
        name.contains("Self.") == false
    else {
        throw StubError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(requirementIndex) uses a dependent typed error. Dependent typed throws requires a separate indirect error-result slot."
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
    return type
}

private func associatedTypeContainer(
    in name: String,
    spellings: [String]
) -> AssociatedTypeContainer? {
    for spelling in spellings {
        if [
            "\(spelling)?",
            "Optional<\(spelling)>",
            "Swift.Optional<\(spelling)>"
        ].contains(name) {
            return .optional
        }
        if [
            "[\(spelling)]",
            "Array<\(spelling)>",
            "Swift.Array<\(spelling)>"
        ].contains(name) {
            return .array
        }
        if [
            "Set<\(spelling)>",
            "Swift.Set<\(spelling)>"
        ].contains(name) {
            return .set
        }
    }
    return nil
}

extension ProtocolRequirement.Flags {
    var isAsync: Bool { bits & 0x20 != 0 }
}

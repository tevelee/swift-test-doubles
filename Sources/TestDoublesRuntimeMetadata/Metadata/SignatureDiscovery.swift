import CTestDoublesTrampoline
import Echo
import Foundation
import TestDoublesRuntimeSupport

package enum GetterEffectDiscoveryPolicy {
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
package func discoverMethods(
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
        guard let abiKind = protocolRequirementKind(req.flags) else {
            throw RuntimeConstructionError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: requirement.dispatchIndex,
                details: "Requirement uses an unknown ABI kind."
            )
        }
        let symbols = requirementSymbolNames(
            requirement,
            witnessTables: witnessTables
        )
        guard symbols.names.isEmpty == false else {
            if symbols.hasWitnessTable {
                throw RuntimeConstructionError.signatureDiscoveryFailed(
                    protocolName: proto.name,
                    requirementIndex: requirement.dispatchIndex,
                    details: "Neither the witness entry nor the protocol requirement descriptor has a resolvable signature symbol. Supply explicit Requirement values."
                )
            }
            throw RuntimeConstructionError.noConformanceFound(protocolName: proto.name)
        }

        var attempted: [String] = []
        var parsed: ParsedWitnessSignature?
        var parsedMangledName: String?
        for mangledName in symbols.names {
            let demangled = RuntimeSymbols.demangle(mangledName)
            attempted.append(demangled)
            if let candidate = parseWitnessSignature(demangled, kind: abiKind) {
                parsed = candidate
                parsedMangledName = mangledName
                break
            }
        }
        guard let parsed, let parsedMangledName else {
            throw RuntimeConstructionError.signatureDiscoveryFailed(
                protocolName: proto.name,
                requirementIndex: requirement.dispatchIndex,
                details: "Could not parse any discovered symbol: \(attempted.joined(separator: "; ")). Supply explicit Requirement values."
            )
        }
        let kind = requirement.kind
        // `isAsync` already mirrors `ProtocolRequirementFlags::isAsync()`, which
        // returns false for read/modify coroutines even though they set the
        // `IsAsyncMask` bit (there it means `isCalleeAllocatedCoroutine`).
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
                mangledSignature: parsedMangledName,
                isArgument: true
            )
        }
        let result = try resolveWitnessValue(
            parsed.returnType,
            protocolDescriptor: proto,
            requirementIndex: requirement.dispatchIndex,
            associatedTypeBindings: associatedTypeBindings,
            mangledSignature: parsedMangledName,
            isArgument: false
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
                    case .selfType, .optionalSelf, .methodGenericParameter:
                        false
                }
            guard kind == .method,
                supportsResultConvention
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
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

package func resilientRequirementSymbolName(
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
                throw RuntimeConstructionError.signatureDiscoveryFailed(
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
                throw RuntimeConstructionError.signatureDiscoveryFailed(
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
    mangledSignature: String,
    isArgument: Bool
) throws -> ResolvedWitnessValue {
    let rawName = syntax.canonicalSpelling
    if rawName.hasPrefix("inout ") {
        let valueName = String(rawName.dropFirst("inout ".count))
        if dynamicSelfValueShape(valueName) != nil
            || containsDynamicSelfReference(valueName)
        {
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
    if valueName.hasPrefix("repeat ") {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) has a parameter-pack argument ('\(valueName)'). "
                + "Automatic Stub does not support requirements whose own generic signature uses a parameter pack. "
                + "Supply explicit Requirement values."
        )
    }
    if let index = methodGenericParameterIndex(valueName) {
        guard isArgument else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) returns a value typed by the requirement's own generic parameter ('\(valueName)'). "
                    + "Automatic Stub does not support producing a value whose type is chosen by the caller. "
                    + "Supply explicit Requirement values."
            )
        }
        return ResolvedWitnessValue(
            type: Any.self,
            convention: .methodGenericParameter(index: index),
            dependency: .independent,
            ownership: ownership
        )
    }
    if let selfShape = dynamicSelfValueShape(valueName) {
        guard isAutoclosure == false else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
        throw RuntimeConstructionError.unsupportedProtocolShape(
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
        throw RuntimeConstructionError.unsupportedProtocolShape(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds associated type '\(binding.name)' inside unsupported type '\(valueName)'. "
                    + "Bound associated-type support accepts recursive combinations of Optional, Array, Set, Dictionary, Result, and linked generic classes, structs, and enums with one or two type parameters."
            )
        }
    }
    guard let concreteSyntax = DemangledTypeSyntax(valueName),
        let type = resolveRuntimeType(
            concreteSyntax,
            containedInMangledSymbol: mangledSignature
        )
    else {
        throw RuntimeConstructionError.signatureDiscoveryFailed(
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

/// Whether a demangled type spelling names a generic parameter belonging to the
/// *requirement itself* rather than to the protocol.
///
/// `Demangle::genericParameterName` (lib/Demangling/NodePrinter.cpp) prints
/// depth-0 parameters as bare letters and deeper ones with the depth appended,
/// so a protocol's `Self` is `"A"` while a method's own first generic parameter
/// is `"A1"`, its second `"B1"`, and so on. A bare letter-plus-digits spelling is
/// unambiguous here because every real type demangles module-qualified
/// (`"MyModule.A1"`), never as a bare identifier.
func isMethodGenericParameter(_ spelling: String) -> Bool {
    methodGenericParameterIndex(spelling) != nil
}

/// The requirement-level generic-parameter index a demangled spelling names,
/// or `nil` if it does not name one.
///
/// The leading letter enumerates the requirement's own generic parameters in
/// declaration order (`A1` is the first, `B1` the second, and so on), so its
/// zero-based alphabet position is the parameter's index directly.
func methodGenericParameterIndex(_ spelling: String) -> Int? {
    var characters = Substring(spelling)
    guard let first = characters.popFirst(),
        first.isUppercase,
        first.isLetter,
        first.isASCII,
        characters.isEmpty == false,
        characters.allSatisfy(\.isNumber)
    else {
        return nil
    }
    return Int(first.asciiValue! - Character("A").asciiValue!)
}

private func dynamicSelfValueShape(
    _ spelling: String
) -> DynamicSelfValueShape? {
    // "A?"/"Self?" are deliberately not matched: swift_demangle (the only
    // demangling entry point this codebase uses) always disables sugar
    // synthesis, so it never emits that spelling -- only the verbose
    // "Optional<...>" forms below are reachable.
    switch spelling {
        case "A", "Self":
            .direct
        case "Optional<A>", "Swift.Optional<A>",
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

private func protocolRequirementKind(
    _ flags: ProtocolRequirement.Flags
) -> ProtocolRequirement.Kind? {
    // Echo's `kind` accessor force-unwraps this enum. Decode the stable flag
    // field first so future requirement kinds fail closed before its semantic
    // `isAsync` accessor is used below.
    ProtocolRequirement.Kind(
        rawValue: UInt8(truncatingIfNeeded: flags.bits & 0xF)
    )
}

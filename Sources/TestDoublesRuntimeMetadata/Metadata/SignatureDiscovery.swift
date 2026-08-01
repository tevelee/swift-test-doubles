import Echo
import Foundation
import TestDoublesRuntimeSupport

package struct GetterEffectHint: @unchecked Sendable {
    package let isThrowing: Bool
    package let typedErrorType: Any.Type?

    package init(isThrowing: Bool, typedErrorType: Any.Type?) {
        self.isThrowing = isThrowing
        self.typedErrorType = typedErrorType
    }
}

package enum GetterEffectDiscoveryPolicy {
    /// Preserves automatic discovery's historical behavior: synchronous
    /// getters are accepted with an unreliable nonthrowing placeholder, while
    /// async getters require an explicit source of truth.
    case automatic
    /// Supplies the effect that Swift's protocol metadata and witness symbols
    /// omit. The caller validates that every getter has exactly one entry.
    case hints([ProtocolLayout.GetterRequirementID: GetterEffectHint])
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
                if let reason = unsupportedRequirementLevelGenericSignatureReason(
                    in: demangled,
                    values: candidate.argumentTypes + [candidate.returnType]
                ) {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: proto.name,
                        reason: "Requirement \(requirement.dispatchIndex) has an unsupported requirement-level generic signature. \(reason)"
                    )
                }
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
        let getterEffect:
            (
                isThrowing: Bool,
                isReliable: Bool,
                typedErrorType: Any.Type?
            )? =
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
        let methodGenericConformanceWitnessCount =
            methodGenericConformanceWitnessCount(
                in: RuntimeSymbols.demangle(parsedMangledName),
                values: parsed.argumentTypes + [parsed.returnType]
            )

        let discoveredTypedError = try resolveTypedError(
            parsed.typedError,
            protocolDescriptor: proto,
            requirementIndex: requirement.dispatchIndex,
            associatedTypeBindings: associatedTypeBindings
        )
        let typedError: (type: Any.Type, dependency: WitnessValueDependency)?
        if let hintedType = getterEffect?.typedErrorType {
            if let discoveredTypedError {
                guard
                    ObjectIdentifier(discoveredTypedError.type)
                        == ObjectIdentifier(hintedType)
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: proto.name,
                        reason:
                            "Getter requirement \(requirement.dispatchIndex) was hinted with typed error '\(runtimeTypeName(hintedType))', but its linked signature declares '\(runtimeTypeName(discoveredTypedError.type))'."
                    )
                }
                typedError = discoveredTypedError
            } else {
                typedError = (hintedType, .independent)
            }
        } else {
            typedError = discoveredTypedError
        }
        if typedError != nil {
            let supportsResultConvention =
                switch result.convention {
                    case .concrete, .associatedType:
                        true
                    case .selfType, .optionalSelf, .nestedOptionalSelf,
                        .arraySelf, .optionalArraySelf,
                        .inoutSelf,
                        .methodGenericParameter,
                        .classMethodGenericParameter,
                        .optionalMethodGenericParameter,
                        .methodGenericParameterPack:
                        false
                }
            guard kind == .method || kind == .getter,
                supportsResultConvention
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: proto.name,
                    reason: "Requirement \(requirement.dispatchIndex) combines typed throws with an unsupported setter, initializer, or Self result convention."
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
                argumentIsVariadic: parsed.argumentIsVariadic,
                argumentIsAutoclosure: parsed.argumentIsAutoclosure,
                result: result,
                protocolName: proto.name,
                typedErrorType: typedError?.type,
                typedErrorDependency: typedError?.dependency ?? .independent,
                selfIsClassConstrained: protocolUsesClassSelfConvention(proto),
                methodGenericConformanceWitnessCount:
                    methodGenericConformanceWitnessCount,
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
        if let symbol = RuntimeSymbols.symbolName(at: function) {
            names.append(symbol)
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
    guard let name = RuntimeSymbols.symbolName(at: descriptor, exact: true) else {
        return nil
    }
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
) throws -> (
    isThrowing: Bool,
    isReliable: Bool,
    typedErrorType: Any.Type?
) {
    switch policy {
        case .automatic:
            guard isAsync == false else {
                throw RuntimeConstructionError.signatureDiscoveryFailed(
                    protocolName: protocolDescriptor.name,
                    requirementIndex: dispatchIndex,
                    details: "Swift witness symbols do not encode whether an async getter throws. Supply GetterEffect hints or explicit Requirement values for effectful getters."
                )
            }
            return (false, false, nil)

        case .hints(let hints):
            let identifier = ProtocolLayout.GetterRequirementID(
                protocolDescriptor: protocolDescriptor,
                witnessIndex: witnessIndex
            )
            guard let hint = hints[identifier] else {
                throw RuntimeConstructionError.signatureDiscoveryFailed(
                    protocolName: protocolDescriptor.name,
                    requirementIndex: dispatchIndex,
                    details: "No GetterEffect hint was supplied for this getter."
                )
            }
            guard hint.typedErrorType == nil || hint.isThrowing else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolDescriptor.name,
                    reason:
                        "Getter requirement \(dispatchIndex) has a typed-error hint but was marked nonthrowing."
                )
            }
            return (hint.isThrowing, true, hint.typedErrorType)

        case .explicitRequirementValidation:
            return (false, false, nil)
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
    var valueName = rawName
    let isInout = valueName.hasPrefix("inout ")
    if valueName.hasPrefix("inout ") {
        valueName.removeFirst("inout ".count)
    }
    if isInout, dynamicSelfValueShape(valueName) != .direct {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) uses unsupported inout argument '\(valueName)'. "
                + "Automatic Stub currently supports inout only for direct dynamic Self."
        )
    }
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
    if let index = methodGenericParameterPackIndex(valueName) {
        guard isArgument else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) returns a parameter pack ('\(valueName)'). "
                    + "Automatic Stub cannot fabricate a caller-chosen pack result."
            )
        }
        guard ownership != .owned else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) consumes a parameter pack. "
                    + "Ownership-aware parameter-pack transport is not implemented."
            )
        }
        return ResolvedWitnessValue(
            type: Any.self,
            convention: .methodGenericParameterPack(index: index),
            dependency: .independent,
            ownership: ownership
        )
    }
    if valueName.hasPrefix("repeat ") {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) expands an unsupported parameter-pack value ('\(valueName)'). "
                + "Automatic Stub supports only one direct borrowed requirement-level parameter pack argument."
        )
    }
    if let index = optionalMethodGenericParameterIndex(valueName) {
        guard isArgument == false else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) embeds a requirement-level generic parameter in Optional argument '\(valueName)'. "
                    + "Automatic Stub currently supports this shape only as a result."
            )
        }
        return ResolvedWitnessValue(
            type: Any.self,
            convention: .optionalMethodGenericParameter(index: index),
            dependency: .independent,
            ownership: ownership
        )
    }
    if let index = methodGenericParameterIndex(valueName) {
        guard isArgument == false || ownership != .owned else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) consumes a requirement-level generic parameter. "
                    + "Ownership-aware generic metadata transport is not implemented."
            )
        }
        return ResolvedWitnessValue(
            type: Any.self,
            convention:
                methodGenericParameterHasClassConstraint(
                    valueName,
                    in: RuntimeSymbols.demangle(mangledSignature)
                )
                ? .classMethodGenericParameter(index: index)
                : .methodGenericParameter(index: index),
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
                    + "Automatic Stub supports direct Self and up to two Optional layers."
            )
        }
        guard
            isArgument
                || (selfShape != .nestedOptional
                    && selfShape != .array
                    && selfShape != .optionalArray)
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason:
                    "Requirement \(requirementIndex) returns a wrapped Self value. "
                    + "Automatic Stub supports nested Optional, Array, and Optional Array Self only as arguments."
            )
        }
        if selfShape == .array {
            return .selfArray(ownership: ownership)
        }
        if selfShape == .optionalArray {
            return .optionalSelfArray(ownership: ownership)
        }
        return .selfValue(
            isOptional: selfShape != .direct,
            isNestedOptional: selfShape == .nestedOptional,
            isInout: isInout,
            ownership: ownership
        )
    }
    if containsDynamicSelfReference(valueName) {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(requirementIndex) embeds Self inside unsupported type '\(valueName)'. "
                + "Automatic Stub supports only direct Self and up to two Optional layers."
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
                    + "Bound associated-type support accepts recursive combinations of Optional, Array, Set, Dictionary, Result, and linked generic classes, structs, and enums with supported metadata-accessor key arguments."
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
    case direct, optional, nestedOptional, array, optionalArray
}

/// Whether a demangled type spelling names a generic parameter belonging to the
/// *requirement itself* rather than to the protocol.
///
/// `Demangle::genericParameterName` (lib/Demangling/NodePrinter.cpp) prints
/// the index in little-endian base 26 with uppercase letters, then appends a
/// nonzero depth. A protocol's `Self` is `"A"`, while a method's own first
/// parameter is `"A1"`, the 27th is `"AB1"`, and so on. Bare spellings are
/// unambiguous here because real types demangle module-qualified
/// (`"MyModule.A1"`), never as bare identifiers.
func isMethodGenericParameter(_ spelling: String) -> Bool {
    methodGenericParameterIndex(spelling) != nil
}

/// The requirement-level generic-parameter index a demangled spelling names
/// (in the demangler's little-endian base-26 spelling), or `nil` if it does
/// not name one or cannot fit in `Int`.
func methodGenericParameterIndex(_ spelling: String) -> Int? {
    let letters = spelling.prefix { $0.isUppercase && $0.isLetter && $0.isASCII }
    let depth = spelling.dropFirst(letters.count)
    guard letters.isEmpty == false,
        depth.isEmpty == false,
        depth.allSatisfy(\.isNumber)
    else {
        return nil
    }

    var multiplier = 1
    var index = 0
    for (offset, letter) in letters.enumerated() {
        let digit = Int(letter.asciiValue! - Character("A").asciiValue!)
        let (term, termOverflow) = digit.multipliedReportingOverflow(by: multiplier)
        let (next, indexOverflow) = index.addingReportingOverflow(term)
        guard termOverflow == false, indexOverflow == false else { return nil }
        index = next
        guard offset + 1 < letters.count else { continue }
        let (nextMultiplier, multiplierOverflow) = multiplier.multipliedReportingOverflow(by: 26)
        guard multiplierOverflow == false else {
            return nil
        }
        multiplier = nextMultiplier
    }
    return index
}

/// The requirement-level generic-parameter index of a direct parameter-pack
/// expansion, or `nil` for ordinary values and nested/unsupported expansions.
func methodGenericParameterPackIndex(_ spelling: String) -> Int? {
    methodGenericParameterPackName(spelling).flatMap(methodGenericParameterIndex)
}

/// The requirement-level generic parameter directly wrapped by one Optional.
func optionalMethodGenericParameterIndex(_ spelling: String) -> Int? {
    optionalMethodGenericParameterName(spelling).flatMap(
        methodGenericParameterIndex
    )
}

private func optionalMethodGenericParameterName(
    _ spelling: String
) -> String? {
    for prefix in ["Swift.Optional<", "Optional<"]
    where spelling.hasPrefix(prefix) && spelling.hasSuffix(">") {
        let start = spelling.index(
            spelling.startIndex,
            offsetBy: prefix.count
        )
        return String(
            spelling[start ..< spelling.index(before: spelling.endIndex)]
        )
    }
    return nil
}

private func methodGenericParameterPackName(_ spelling: String) -> String? {
    let expansion: Substring =
        spelling.first == "(" && spelling.last == ")"
        ? spelling.dropFirst().dropLast()
        : Substring(spelling)
    guard expansion.hasPrefix("repeat ") else { return nil }
    return String(expansion.dropFirst("repeat ".count))
}

private struct MethodGenericParameters {
    let ordinary: Set<String>
    let packs: Set<String>

    var all: Set<String> {
        ordinary.union(packs)
    }
}

private func methodGenericParameters(
    in values: [DemangledTypeSyntax]
) -> MethodGenericParameters {
    var ordinary: Set<String> = []
    var packs: Set<String> = []

    for value in values {
        let spelling = value.canonicalSpelling
        if methodGenericParameterIndex(spelling) != nil {
            ordinary.insert(spelling)
        } else if let parameter = optionalMethodGenericParameterName(spelling),
            methodGenericParameterIndex(parameter) != nil
        {
            ordinary.insert(parameter)
        } else if let parameter = methodGenericParameterPackName(spelling),
            methodGenericParameterIndex(parameter) != nil
        {
            packs.insert(parameter)
        }
    }

    return MethodGenericParameters(ordinary: ordinary, packs: packs)
}

private func methodGenericConformanceWitnessCount(
    in demangled: String,
    values: [DemangledTypeSyntax]
) -> Int {
    let parameters = methodGenericParameters(in: values)
    var count = 0
    for parameter in parameters.all {
        for marker in ["where \(parameter): ", ", \(parameter): "] {
            var remaining = demangled[...]
            while let range = remaining.range(of: marker) {
                let constraintStart = range.upperBound
                let suffix = remaining[constraintStart...]
                let constraintEnd =
                    suffix.firstIndex(where: { $0 == "," || $0 == ">" })
                    ?? suffix.endIndex
                let constraint = suffix[..<constraintEnd]
                if constraint != "AnyObject"
                    && constraint != "~Swift.Copyable"
                    && constraint != "~Swift.Escapable"
                {
                    count += 1
                }
                remaining = suffix[constraintEnd...]
            }
        }
    }
    return count
}

/// The fabricated witness reserves metadata words for copyable, escapable
/// method generic parameters. Protocol constraints append witness-table words
/// after that metadata; recording does not need to inspect them, so the call
/// frame may safely leave those trailing words opaque.
private func unsupportedRequirementLevelGenericSignatureReason(
    in demangled: String,
    values: [DemangledTypeSyntax]
) -> String? {
    let parameters = methodGenericParameters(in: values)
    guard parameters.all.isEmpty == false else { return nil }

    for parameter in parameters.all
    where demangledGenericParameterHasConstraint(
        parameter,
        in: demangled
    ) {
        if parameters.packs.contains(parameter) {
            return "Protocol-constrained parameter packs carry additional witness packs whose transport is not implemented."
        }
        if demangled.contains("\(parameter): ~Swift.Copyable") {
            return "`~Copyable` parameters cannot be copied into the recorder's escaping Any storage."
        }
        if demangled.contains("\(parameter): ~Swift.Escapable") {
            return "`~Escapable` parameters may have lifetime-dependent storage that cannot escape into the recorder."
        }
        if demangled.contains("\(parameter) ==")
            || demangled.contains("where \(parameter) ==")
        {
            return "Same-type constraints can change generic metadata identity and are not implemented."
        }
        // Ordinary protocol constraints preserve the indirect value plus
        // metadata ABI already decoded below. Their additional conformance
        // witnesses follow the metadata and are irrelevant to value capture.
    }
    return nil
}

private func methodGenericParameterHasClassConstraint(
    _ parameter: String,
    in demangled: String
) -> Bool {
    let prefixes = [
        "where \(parameter): AnyObject",
        ", \(parameter): AnyObject"
    ]
    return prefixes.contains { demangled.contains($0) }
}

private func demangledGenericParameterHasConstraint(
    _ parameter: String,
    in demangled: String
) -> Bool {
    let prefixes = ["where \(parameter):", "where \(parameter) ==", ", \(parameter):", ", \(parameter) =="]
    return prefixes.contains { demangled.contains($0) }
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
        case "Optional<Optional<A>>", "Optional<Swift.Optional<A>>",
            "Swift.Optional<Optional<A>>", "Swift.Optional<Swift.Optional<A>>",
            "Optional<Optional<Self>>", "Optional<Swift.Optional<Self>>",
            "Swift.Optional<Optional<Self>>",
            "Swift.Optional<Swift.Optional<Self>>":
            .nestedOptional
        case "Array<A>", "Swift.Array<A>",
            "Array<Self>", "Swift.Array<Self>":
            .array
        case "Optional<Array<A>>", "Optional<Swift.Array<A>>",
            "Swift.Optional<Array<A>>", "Swift.Optional<Swift.Array<A>>",
            "Optional<Array<Self>>", "Optional<Swift.Array<Self>>",
            "Swift.Optional<Array<Self>>",
            "Swift.Optional<Swift.Array<Self>>":
            .optionalArray
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

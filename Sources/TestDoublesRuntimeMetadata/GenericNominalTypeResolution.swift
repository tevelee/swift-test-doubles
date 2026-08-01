import Echo
import TestDoublesRuntimeSupport

package struct GenericClassID: Equatable, Sendable {
    package let name: String
    package let descriptorAddress: UInt

    package init(name: String, descriptorAddress: UInt) {
        self.name = name
        self.descriptorAddress = descriptorAddress
    }
}

package struct ResolvedGenericClassType: Sendable {
    package let type: Any.Type
    package let constructor: GenericClassID

    package init(type: Any.Type, constructor: GenericClassID) {
        self.type = type
        self.constructor = constructor
    }
}

package enum GenericValueKind: String, Equatable, Sendable {
    case `struct`
    case `enum`
}

package struct GenericValueID: Equatable, Sendable {
    package let name: String
    package let descriptorAddress: UInt
    package let kind: GenericValueKind

    package init(
        name: String,
        descriptorAddress: UInt,
        kind: GenericValueKind
    ) {
        self.name = name
        self.descriptorAddress = descriptorAddress
        self.kind = kind
    }
}

package struct ResolvedGenericValueType: Sendable {
    package let type: Any.Type
    package let constructor: GenericValueID

    package init(type: Any.Type, constructor: GenericValueID) {
        self.type = type
        self.constructor = constructor
    }
}

/// Instantiates a linked generic nominal type without requiring its source or
/// a macro-generated registry. `resolvedGenericAccessorType` supplies the
/// context's ordered type-metadata and witness-table key arguments before
/// falling back to failing closed.
package func genericNominalType(named name: String) -> Any.Type? {
    guard let application = genericApplication(name) else {
        return nil
    }
    guard let argumentNames = topLevelComponents(in: application.arguments) else {
        return nil
    }

    for kind in ["V", "O", "C"] {
        guard
            let descriptor = genericNominalDescriptor(
                named: application.constructor,
                kind: kind
            ),
            let context = descriptor.genericContext,
            let type = resolvedGenericAccessorType(
                descriptor: descriptor,
                context: context,
                argumentSpellings: argumentNames
            ),
            application.constructor != "Swift.InlineArray"
                || inlineArrayHasCopyableElements(type)
        else { continue }
        return type
    }
    return nil
}

/// Resolves a generic context's accessor with its ordered key arguments.
/// Shared by `genericNominalType` and `genericClassType`.
///
/// Key argument layout follows swiftlang/swift's docs/ABI/TypeMetadata.rst:
/// each parameter's type metadata first, then each requirement's witness
/// table, in requirement-descriptor order.
///
/// Fails closed (`nil`) for non-protocol key requirements, requirements not
/// attributable to a depth-0 parameter, non-conforming arguments, or pack
/// parameters. Integer value parameters need matching `.int` descriptors.
private func resolvedGenericAccessorType(
    descriptor: any TypeContextDescriptor,
    context: GenericContext,
    argumentSpellings: [String]
) -> Any.Type? {
    guard
        let parameterArguments = genericParameterArguments(
            context: context,
            spellings: argumentSpellings
        )
    else {
        return nil
    }
    return resolvedGenericAccessorType(
        descriptor: descriptor,
        context: context,
        parameterArguments: parameterArguments
    )
}

private func resolvedGenericAccessorType(
    descriptor: any TypeContextDescriptor,
    context: GenericContext,
    arguments: [Any.Type]
) -> Any.Type? {
    resolvedGenericAccessorType(
        descriptor: descriptor,
        context: context,
        parameterArguments: arguments.map(GenericArgument.metadata)
    )
}

private func resolvedGenericAccessorType(
    descriptor: any TypeContextDescriptor,
    context: GenericContext,
    parameterArguments: [GenericArgument]
) -> Any.Type? {
    guard
        let genericArguments = genericAccessorArguments(
            context: context,
            parameterArguments: parameterArguments
        )
    else {
        return nil
    }
    return descriptor.accessor(
        .complete,
        genericArguments: genericArguments
    ).type
}

/// Interprets source-level generic arguments only after the target
/// descriptor's parameter kinds are known. Ordinary parameters recursively
/// resolve as types. Value parameters accept canonical nonnegative decimal
/// integers whose descriptor is `.int`. Packs and unknown future value
/// representations remain fail-closed.
private func genericParameterArguments(
    context: GenericContext,
    spellings: [String]
) -> [GenericArgument]? {
    let parameters = context.parameters
    guard parameters.count == spellings.count,
        parameters.allSatisfy(\.hasKeyArgument)
    else {
        return nil
    }

    let valueDescriptors = context.genericValueDescriptors
    guard
        valueDescriptors.count
            == parameters.filter({ $0.kind == .value }).count
    else {
        return nil
    }

    var valueDescriptorIndex = 0
    var arguments: [GenericArgument] = []
    arguments.reserveCapacity(parameters.count)
    for (parameter, spelling) in zip(parameters, spellings) {
        switch parameter.kind {
            case .type:
                guard let type = resolveRuntimeType(spelling) else {
                    return nil
                }
                arguments.append(.metadata(type))
            case .value:
                guard valueDescriptors.indices.contains(valueDescriptorIndex),
                    valueDescriptors[valueDescriptorIndex].type == .int,
                    let value = nonnegativeIntegerValue(spelling)
                else {
                    return nil
                }
                valueDescriptorIndex += 1
                arguments.append(.value(value))
            case .typePack:
                return nil
        }
    }
    guard valueDescriptorIndex == valueDescriptors.count else { return nil }
    return arguments
}

private func nonnegativeIntegerValue(_ spelling: String) -> UInt? {
    let bytes = spelling.utf8
    guard bytes.isEmpty == false,
        bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }),
        bytes.count == 1 || bytes.first != 48,
        let value = UInt(spelling),
        value <= UInt(Int.max)
    else {
        return nil
    }
    return value
}

/// Builds the complete, ordered ABI key used by
/// `resolvedGenericAccessorType`. Every ordinary type parameter and every key
/// protocol requirement contributes one argument; arity is bounded only by
/// the generic context's exact `numKeyArguments` count.
private func genericAccessorArguments(
    context: GenericContext,
    parameterArguments: [GenericArgument]
) -> [GenericArgument]? {
    let parameters = context.parameters
    guard parameters.count == parameterArguments.count,
        zip(parameters, parameterArguments).allSatisfy({
            return switch ($0.0.kind, $0.1) {
                case (.type, .metadata(_)), (.value, .value(_)):
                    true
                default:
                    false
            }
        })
    else {
        return nil
    }
    let requirements = context.requirements.filter(\.flags.hasKeyArgument)
    guard
        requirements.allSatisfy({
            $0.flags.kind == .protocol
                && !$0.flags.isPackRequirement
                && !$0.flags.isValueRequirement
        })
    else {
        return nil
    }

    var genericArguments = parameterArguments
    for requirement in requirements {
        guard
            let index = depthZeroGenericParameterIndex(
                mangledName: requirement.paramMangledName
            ),
            parameterArguments.indices.contains(index),
            case .metadata(let type) = parameterArguments[index]
        else {
            return nil
        }
        guard
            let witnessTable = swift_conformsToProtocol(
                type: type,
                protocol: requirement.protocol
            )
        else {
            return nil
        }
        genericArguments.append(.witnessTable(witnessTable))
    }

    guard context.numKeyArguments == genericArguments.count else { return nil }
    return genericArguments
}

/// Decodes a direct, depth-0 generic-parameter reference from a generic
/// requirement's mangled parameter name, per swiftlang/swift's
/// docs/ABI/Mangling.rst grammar: `type ::= 'x'` (depth 0, index 0) or
/// `type ::= 'q' GENERIC-PARAM-INDEX` where `GENERIC-PARAM-INDEX ::= '_'`
/// (index 0, only reachable through `q` for other contexts) `| NATURAL '_'`
/// (index N+1) `| 'd' INDEX INDEX` (depth > 0). Returns nil for anything
/// else -- a deeper depth (`qd...`), an associated-type reference, or a
/// parameter pack -- so an unrecognized requirement shape fails closed
/// instead of being attributed to the wrong parameter.
private func depthZeroGenericParameterIndex(mangledName: UnsafeRawPointer) -> Int? {
    let name = String(cString: mangledName.assumingMemoryBound(to: CChar.self))
    if name == "x" { return 0 }
    guard name.hasPrefix("q"), name.hasSuffix("_") else { return nil }
    let body = name.dropFirst().dropLast()
    guard !body.hasPrefix("d") else { return nil }
    if body.isEmpty { return 1 }
    guard let natural = Int(body), natural >= 0 else { return nil }
    return natural + 2
}

/// Reconstructs metadata only for a linked, top-level generic Swift class.
///
/// A constrained parameter (`Box<Value: Hashable>`) resolves through the
/// same witness-table key-argument path `resolvedGenericAccessorType` uses
/// for any kind; arity is bounded by the linked generic context's exact key
/// arguments rather than an independent library limit.
package func genericClassType(
    named constructorName: String,
    arguments: [Any.Type]
) -> ResolvedGenericClassType? {
    guard arguments.isEmpty == false,
        let descriptor = genericNominalDescriptor(
            named: constructorName,
            kind: "C"
        ),
        let context = descriptor.genericContext,
        context.numParams == arguments.count,
        context.numExtraArguments == 0,
        let type = resolvedGenericAccessorType(
            descriptor: descriptor,
            context: context,
            arguments: arguments
        ),
        reflect(type).kind == .class,
        let reconstructedDescriptor = reflectClass(type)?.descriptor,
        reconstructedDescriptor.ptr == descriptor.ptr
    else {
        return nil
    }
    return ResolvedGenericClassType(
        type: type,
        constructor: GenericClassID(
            name: constructorName,
            descriptorAddress: UInt(bitPattern: descriptor.ptr)
        )
    )
}

/// Reconstructs metadata for a linked, top-level generic struct or enum whose
/// formal associated-type substitution keeps the complete value opaque.
///
/// The protocol witness ABI passes and returns these values indirectly, even
/// if a concrete specialization would fit in registers. Arity follows the
/// linked descriptor's generic context and exact key-argument count.
package func genericValueType(
    named constructorName: String,
    arguments: [Any.Type]
) -> ResolvedGenericValueType? {
    guard arguments.isEmpty == false else { return nil }

    for (symbolKind, valueKind) in [("V", GenericValueKind.struct), ("O", .enum)] {
        guard
            let descriptor = genericNominalDescriptor(
                named: constructorName,
                kind: symbolKind
            ),
            let context = descriptor.genericContext,
            context.numParams == arguments.count,
            context.numExtraArguments == 0,
            let type = resolvedGenericAccessorType(
                descriptor: descriptor,
                context: context,
                arguments: arguments
            ),
            reflect(type).kind == (valueKind == .struct ? .struct : .enum)
        else {
            continue
        }

        return ResolvedGenericValueType(
            type: type,
            constructor: GenericValueID(
                name: constructorName,
                descriptorAddress: UInt(bitPattern: descriptor.ptr),
                kind: valueKind
            )
        )
    }
    return nil
}

private func genericNominalDescriptor(
    named constructorName: String,
    kind: String
) -> (any TypeContextDescriptor)? {
    let components = constructorName.split(separator: ".").map(String.init)
    guard components.count >= 2 else { return nil }
    if components.count == 2 {
        let module = components[0]
        let nominal = components[1]
        let moduleMangle =
            module == "Swift" ? "s" : "\(module.utf8.count)\(module)"
        let prefix = "\(moduleMangle)\(nominal.utf8.count)\(nominal)"
        if let pointer = RuntimeSymbols.rawSymbol(named: "$s\(prefix)\(kind)Mn") {
            return typeContextDescriptor(at: UnsafeRawPointer(pointer), kind: kind)
        }
    }

    // Swift's standard library abbreviates some nominal names in mangled
    // symbols (`Range`, for example), and nested declarations may use
    // substitutions. The loaded image type sections retain the complete parent
    // chain, so compare semantic identities instead of teaching this resolver
    // spelling exceptions.
    return types.lazy.compactMap { descriptor in
        guard
            let typeDescriptor = descriptor as? any TypeContextDescriptor,
            qualifiedContextName(
                typeDescriptor.name,
                parent: typeDescriptor.parent
            ) == constructorName,
            typeContextDescriptorKind(typeDescriptor) == kind
        else {
            return nil
        }
        return typeDescriptor
    }.first
}

private func typeContextDescriptor(
    at pointer: UnsafeRawPointer,
    kind: String
) -> (any TypeContextDescriptor)? {
    switch kind {
        case "V":
            unsafeBitCast(
                pointer,
                to: StructDescriptor.self
            )
        case "O":
            unsafeBitCast(
                pointer,
                to: EnumDescriptor.self
            )
        case "C":
            unsafeBitCast(
                pointer,
                to: ClassDescriptor.self
            )
        default: nil
    }
}

private func typeContextDescriptorKind(_ descriptor: any TypeContextDescriptor) -> String? {
    switch descriptor {
        case is StructDescriptor: "V"
        case is EnumDescriptor: "O"
        case is ClassDescriptor: "C"
        default: nil
    }
}

package func genericApplication(
    _ name: String
) -> (constructor: String, arguments: String)? {
    guard name.last == ">" else { return nil }
    for index in name.indices where name[index] == "<" {
        return (
            String(name[..<index]),
            String(name[name.index(after: index) ..< name.index(before: name.endIndex)])
        )
    }
    return nil
}

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
    let arguments = argumentNames.compactMap(resolveRuntimeType)
    guard arguments.count == argumentNames.count else { return nil }

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
                arguments: arguments
            )
        else { continue }
        return type
    }
    return nil
}

/// Resolves a generic context's accessor with its ordered key arguments.
/// Shared by `genericNominalType` (any kind) and `genericClassType` (classes
/// only, for dependent-type resolution's linked-class path).
///
/// Key arguments are laid out per swiftlang/swift's
/// docs/ABI/TypeMetadata.rst: every parameter's own type metadata first (one
/// per parameter, in declaration order), then every requirement's witness
/// table in requirement-descriptor order. Echo's `GenericArgument` API
/// preserves that ABI distinction and passes the resulting contiguous layout
/// to the metadata accessor.
///
/// Fails closed -- returns nil -- whenever a key requirement is a
/// same-type/base-class/layout constraint rather than a protocol conformance,
/// whenever a requirement can't be attributed to a specific depth-0
/// parameter, whenever the resolved argument doesn't actually conform, or
/// whenever the context contains a pack or value parameter.
private func resolvedGenericAccessorType(
    descriptor: any TypeContextDescriptor,
    context: GenericContext,
    arguments: [Any.Type]
) -> Any.Type? {
    guard
        let genericArguments = genericAccessorArguments(
            context: context,
            arguments: arguments
        )
    else {
        return nil
    }
    return descriptor.accessor(
        .complete,
        genericArguments: genericArguments
    ).type
}

/// Builds the complete, ordered ABI key used by
/// `resolvedGenericAccessorType`. Every ordinary type parameter and every key
/// protocol requirement contributes one argument; arity is bounded only by
/// the generic context's exact `numKeyArguments` count.
private func genericAccessorArguments(
    context: GenericContext,
    arguments: [Any.Type]
) -> [GenericArgument]? {
    let parameters = context.parameters
    guard parameters.count == arguments.count,
        parameters.allSatisfy({ $0.kind == .type && $0.hasKeyArgument })
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

    var genericArguments = arguments.map(GenericArgument.metadata)
    for requirement in requirements {
        guard
            let index = depthZeroGenericParameterIndex(
                mangledName: requirement.paramMangledName
            ),
            arguments.indices.contains(index)
        else {
            return nil
        }
        guard
            let witnessTable = swift_conformsToProtocol(
                type: arguments[index],
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
/// for any kind; this only ever declines a class whose accessor needs more
/// than one or two key arguments' worth of parameters, or a constructor
/// whose accessor doesn't actually round-trip to a class.
package func genericClassType(
    named constructorName: String,
    arguments: [Any.Type]
) -> ResolvedGenericClassType? {
    guard (1 ... 2).contains(arguments.count),
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
/// if a concrete specialization would fit in registers. Restricting this to
/// one or two type parameters keeps the reconstruction contract aligned with
/// the established associated-dependent class slice.
package func genericValueType(
    named constructorName: String,
    arguments: [Any.Type]
) -> ResolvedGenericValueType? {
    guard (1 ... 2).contains(arguments.count) else { return nil }

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
    guard components.count == 2 else { return nil }
    let module = components[0]
    let nominal = components[1]
    let moduleMangle =
        module == "Swift" ? "s" : "\(module.utf8.count)\(module)"
    let prefix = "\(moduleMangle)\(nominal.utf8.count)\(nominal)"
    guard let pointer = RuntimeSymbols.rawSymbol(named: "$s\(prefix)\(kind)Mn")
    else {
        return nil
    }
    return switch kind {
        case "V":
            unsafeBitCast(
                UnsafeRawPointer(pointer),
                to: StructDescriptor.self
            )
        case "O":
            unsafeBitCast(
                UnsafeRawPointer(pointer),
                to: EnumDescriptor.self
            )
        case "C":
            unsafeBitCast(
                UnsafeRawPointer(pointer),
                to: ClassDescriptor.self
            )
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

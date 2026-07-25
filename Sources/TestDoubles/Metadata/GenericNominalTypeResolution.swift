import Echo

struct GenericClassID: Equatable, Sendable {
    let name: String
    let descriptorAddress: UInt
}

struct ResolvedGenericClassType: Sendable {
    let type: Any.Type
    let constructor: GenericClassID
}

/// Instantiates a public generic nominal type without requiring its source or
/// a macro-generated registry. When a parameter carries a protocol
/// requirement, `numKeyArguments` exceeds the plain type-argument count by
/// one witness table per constraint; `constrainedGenericNominalType` resolves
/// those before falling back to failing closed.
func genericNominalType(named name: String) -> Any.Type? {
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
            let context = descriptor.genericContext
        else { continue }
        if context.numKeyArguments == arguments.count {
            return callGenericAccessor(descriptor.accessor, arguments: arguments)
        }
        if let type = constrainedGenericNominalType(
            descriptor: descriptor,
            context: context,
            arguments: arguments
        ) {
            return type
        }
    }
    return nil
}

/// Extends `genericNominalType` to parameters with one or more protocol
/// conformance requirements (`Range<Bound: Comparable>`, a user's own
/// `Box<T: Codable>`, and so on), which the unconstrained accessor call above
/// always declines because it only ever supplies type-metadata arguments.
///
/// Key arguments are laid out per swiftlang/swift's
/// docs/ABI/TypeMetadata.rst: every parameter's own type metadata first (one
/// per parameter, in declaration order), then every requirement's witness
/// table second, grouped by the parameter it constrains -- confirmed against
/// stdlib/public/runtime/Metadata.cpp's `installGenericArguments`, which
/// copies the whole key as one flat, contiguous array. Rather than
/// reconstruct that buffer by hand, this defers entirely to Echo's own
/// `MetadataAccessFunction` witness-table call convention
/// (`callAsFunction(_:_:) -> ... (Any.Type, WitnessTable?)...`), which
/// already implements the identical layout.
///
/// Fails closed -- returns nil -- whenever a parameter carries more than one
/// protocol requirement (Echo's call convention carries at most one witness
/// table per key argument), whenever a requirement is a same-type/base-class/
/// layout constraint rather than a protocol conformance, whenever a
/// requirement can't be attributed to a specific depth-0 parameter, or
/// whenever the resolved argument doesn't actually conform.
private func constrainedGenericNominalType(
    descriptor: any TypeContextDescriptor,
    context: GenericContext,
    arguments: [Any.Type]
) -> Any.Type? {
    guard
        let keyArguments = constrainedGenericKeyArguments(
            context: context,
            arguments: arguments
        )
    else {
        return nil
    }
    return callConstrainedGenericAccessor(descriptor.accessor, keyArguments: keyArguments)
}

/// Builds the (type, witness table) key-argument list a constrained
/// generic context's accessor needs, shared by `constrainedGenericNominalType`
/// (any kind) and `genericClassType` (classes only, for dependent-type
/// resolution's linked-class path). See `constrainedGenericNominalType`'s
/// documentation for the layout this reconstructs and what it declines.
private func constrainedGenericKeyArguments(
    context: GenericContext,
    arguments: [Any.Type]
) -> [(type: Any.Type, witnessTable: WitnessTable?)]? {
    let parameters = context.parameters
    guard parameters.count == arguments.count,
        parameters.allSatisfy({ $0.kind == .type && $0.hasKeyArgument })
    else {
        return nil
    }
    let requirements = context.requirements
    guard
        requirements.allSatisfy({ !$0.flags.hasKeyArgument || $0.flags.kind == .protocol })
    else {
        return nil
    }

    var keyArguments: [(type: Any.Type, witnessTable: WitnessTable?)] = []
    for (index, argument) in arguments.enumerated() {
        let matching = requirements.filter {
            $0.flags.kind == .protocol && $0.flags.hasKeyArgument
                && depthZeroGenericParameterIndex(mangledName: $0.paramMangledName) == index
        }
        guard matching.count <= 1 else { return nil }
        guard let requirement = matching.first else {
            keyArguments.append((argument, nil))
            continue
        }
        guard
            let witnessTable = swift_conformsToProtocol(
                type: argument,
                protocol: requirement.protocol
            )
        else {
            return nil
        }
        keyArguments.append((argument, witnessTable))
    }

    let witnessCount = keyArguments.filter { $0.witnessTable != nil }.count
    guard context.numKeyArguments == arguments.count + witnessCount else { return nil }
    return keyArguments
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

private func callConstrainedGenericAccessor(
    _ accessor: MetadataAccessFunction,
    keyArguments: [(type: Any.Type, witnessTable: WitnessTable?)]
) -> Any.Type? {
    switch keyArguments.count {
        case 0:
            return accessor(.complete).type
        case 1:
            return accessor(
                .complete,
                (keyArguments[0].type, keyArguments[0].witnessTable)
            ).type
        case 2:
            return accessor(
                .complete,
                (keyArguments[0].type, keyArguments[0].witnessTable),
                (keyArguments[1].type, keyArguments[1].witnessTable)
            ).type
        case 3:
            return accessor(
                .complete,
                (keyArguments[0].type, keyArguments[0].witnessTable),
                (keyArguments[1].type, keyArguments[1].witnessTable),
                (keyArguments[2].type, keyArguments[2].witnessTable)
            ).type
        case 4:
            return accessor(
                .complete,
                (keyArguments[0].type, keyArguments[0].witnessTable),
                (keyArguments[1].type, keyArguments[1].witnessTable),
                (keyArguments[2].type, keyArguments[2].witnessTable),
                (keyArguments[3].type, keyArguments[3].witnessTable)
            ).type
        default:
            return nil
    }
}

/// Reconstructs metadata only for a linked, top-level generic Swift class.
///
/// A constrained parameter (`Box<Value: Hashable>`) resolves through the
/// same witness-table key-argument path `constrainedGenericNominalType`
/// uses; this only ever declines a class whose accessor needs more than
/// one or two key arguments' worth of parameters, or a constructor whose
/// accessor doesn't actually round-trip to a class.
func genericClassType(
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
        context.numExtraArguments == 0
    else {
        return nil
    }

    let type: Any.Type?
    if context.numKeyArguments == arguments.count {
        type = callGenericAccessor(descriptor.accessor, arguments: arguments)
    } else if let keyArguments = constrainedGenericKeyArguments(
        context: context,
        arguments: arguments
    ) {
        type = callConstrainedGenericAccessor(
            descriptor.accessor,
            keyArguments: keyArguments
        )
    } else {
        type = nil
    }

    guard let type,
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

private func callGenericAccessor(
    _ accessor: MetadataAccessFunction,
    arguments: [Any.Type]
) -> Any.Type? {
    switch arguments.count {
        case 0: return accessor(.complete).type
        case 1: return accessor(.complete, arguments[0]).type
        case 2:
            return accessor(.complete, arguments[0], arguments[1]).type
        case 3:
            return accessor(
                .complete,
                arguments[0],
                arguments[1],
                arguments[2]
            ).type
        case 4:
            return accessor(
                .complete,
                arguments[0],
                arguments[1],
                arguments[2],
                arguments[3]
            ).type
        default:
            return nil
    }
}

func genericApplication(
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

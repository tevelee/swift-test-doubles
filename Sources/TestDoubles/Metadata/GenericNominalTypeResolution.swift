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
/// a macro-generated registry. The descriptor tells us exactly how many
/// runtime key arguments its metadata accessor accepts, so constrained types
/// that also need witness tables fail closed.
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
            )
        else { continue }
        guard let context = descriptor.genericContext,
            context.numKeyArguments == arguments.count
        else {
            continue
        }
        return callGenericAccessor(descriptor.accessor, arguments: arguments)
    }
    return nil
}

/// Reconstructs metadata only for a linked, top-level generic Swift class.
///
/// This deliberately excludes constrained constructors and constructors whose
/// accessor needs anything besides one or two type-metadata arguments.
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
        context.numKeyArguments == arguments.count,
        context.numExtraArguments == 0,
        context.numRequirements == 0,
        context.parameters.allSatisfy({
            $0.kind == .type && $0.hasKeyArgument
        }),
        let type = callGenericAccessor(
            descriptor.accessor,
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

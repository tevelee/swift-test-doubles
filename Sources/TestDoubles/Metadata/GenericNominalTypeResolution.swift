import Echo

/// Instantiates a public generic nominal type without requiring its source or
/// a macro-generated registry. The descriptor tells us exactly how many
/// runtime key arguments its metadata accessor accepts, so constrained types
/// that also need witness tables fail closed.
func genericNominalType(named name: String) -> Any.Type? {
    guard let application = genericApplication(name) else {
        return nil
    }
    let components = application.constructor.split(separator: ".").map(String.init)
    guard components.count == 2 else { return nil }
    guard let argumentNames = topLevelComponents(in: application.arguments) else {
        return nil
    }
    let arguments = argumentNames.compactMap(resolveRuntimeType)
    guard arguments.count == argumentNames.count else { return nil }

    let module = components[0]
    let nominal = components[1]
    let moduleMangle =
        module == "Swift" ? "s" : "\(module.utf8.count)\(module)"
    let prefix = "\(moduleMangle)\(nominal.utf8.count)\(nominal)"
    for kind in ["V", "O", "C"] {
        guard let descriptorPointer = RuntimeSymbols.rawSymbol(named: "$s\(prefix)\(kind)Mn")
        else {
            continue
        }
        let descriptor: any TypeContextDescriptor
        switch kind {
            case "V":
                descriptor = unsafeBitCast(
                    UnsafeRawPointer(descriptorPointer),
                    to: StructDescriptor.self
                )
            case "O":
                descriptor = unsafeBitCast(
                    UnsafeRawPointer(descriptorPointer),
                    to: EnumDescriptor.self
                )
            case "C":
                descriptor = unsafeBitCast(
                    UnsafeRawPointer(descriptorPointer),
                    to: ClassDescriptor.self
                )
            default:
                preconditionFailure("Nominal kind was validated by construction.")
        }
        guard let context = descriptor.genericContext,
            context.numKeyArguments == arguments.count
        else {
            continue
        }
        return callGenericAccessor(descriptor.accessor, arguments: arguments)
    }
    return nil
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

private func genericApplication(
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

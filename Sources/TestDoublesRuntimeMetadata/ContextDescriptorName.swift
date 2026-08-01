import Echo

/// Reconstructs the source-level name a context descriptor retains through
/// its parent chain. This remains stable even when the linker's mangling uses
/// substitutions for nested declarations.
func qualifiedContextName(
    _ name: String,
    parent: (any ContextDescriptor)?
) -> String? {
    var components = [name]
    var context = parent
    while let current = context {
        if let module = current as? ModuleDescriptor {
            components.append(module.name)
            return components.reversed().joined(separator: ".")
        }
        if let type = current as? any TypeContextDescriptor {
            components.append(type.name)
            context = type.parent
            continue
        }
        if let parentProtocol = current as? ProtocolDescriptor {
            components.append(parentProtocol.name)
            context = parentProtocol.parent
            continue
        }
        return nil
    }
    return nil
}

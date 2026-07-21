import Echo

extension Stub.Requirement.Value {
    func resolve(
        protocolDescriptor: ProtocolDescriptor,
        bindings: AssociatedTypeBindings
    ) throws -> ResolvedWitnessValue {
        switch source {
            case .concrete(let type):
                return ResolvedWitnessValue(
                    type: type,
                    convention: .concrete,
                    dependency: .independent,
                    ownership: ownership
                )
            case .associatedType(let name):
                return .associatedType(
                    binding: try bindings.binding(named: name, declaredBy: protocolDescriptor),
                    ownership: ownership
                )
            case .associatedTypeContainer(let name, let container):
                return try .associatedType(
                    binding: try bindings.binding(named: name, declaredBy: protocolDescriptor),
                    container: container,
                    ownership: ownership
                )
            case .associatedTypeDictionary(let key, let value):
                let resolvedKey = try key.resolve(
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                )
                let resolvedValue = try value.resolve(
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                )
                return try .associatedTypeDictionary(
                    keyType: resolvedKey.type,
                    keyDependency: resolvedKey.dependency,
                    valueType: resolvedValue.type,
                    valueDependency: resolvedValue.dependency,
                    protocolName: protocolDescriptor.name,
                    ownership: ownership
                )
            case .selfType(let isOptional):
                return .selfValue(isOptional: isOptional, ownership: ownership)
        }
    }
}

extension Stub.Requirement.Value.DictionaryComponent {
    func resolve(
        protocolDescriptor: ProtocolDescriptor,
        bindings: AssociatedTypeBindings
    ) throws -> (type: Any.Type, dependency: WitnessValueDependency) {
        switch self {
            case .concrete(let type):
                (type, .independent)
            case .associatedType(let name):
                try resolvedAssociatedType(
                    named: name,
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                )
        }
    }
}

private func resolvedAssociatedType(
    named name: String,
    protocolDescriptor: ProtocolDescriptor,
    bindings: AssociatedTypeBindings
) throws -> (type: Any.Type, dependency: WitnessValueDependency) {
    let binding = try bindings.binding(
        named: name,
        declaredBy: protocolDescriptor
    )
    return (binding.type, .associatedType(id: binding.id))
}

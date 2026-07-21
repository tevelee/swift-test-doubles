import Echo

extension Stub.Requirement.Value {
    func resolve(
        protocolDescriptor: ProtocolDescriptor,
        bindings: AssociatedTypeBindings
    ) throws -> ResolvedWitnessValue {
        if case .selfType(let isOptional) = source {
            return .selfValue(isOptional: isOptional, ownership: ownership)
        }
        return .resolved(
            try source.resolveDependentType(
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            ),
            ownership: ownership
        )
    }
}

extension Stub.Requirement.Value.Source {
    func resolveDependentType(
        protocolDescriptor: ProtocolDescriptor,
        bindings: AssociatedTypeBindings
    ) throws -> ResolvedDependentType {
        switch self {
            case .concrete(let type):
                return ResolvedDependentType(
                    type: type,
                    dependency: .independent
                )
            case .associatedType(let name):
                return .associatedType(
                    binding: try bindings.binding(
                        named: name,
                        declaredBy: protocolDescriptor
                    )
                )
            case .optional(let wrapped):
                return try wrapped.resolveDependentType(
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ).optional()
            case .array(let element):
                return try element.resolveDependentType(
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ).array()
            case .set(let element):
                let resolved = try element.resolveDependentType(
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                )
                return try resolved.set(
                    protocolName: protocolDescriptor.name,
                    sourceDescription: runtimeTypeName(resolved.type)
                )
            case .dictionary(let key, let value):
                return try .dictionary(
                    key: key.resolveDependentType(
                        protocolDescriptor: protocolDescriptor,
                        bindings: bindings
                    ),
                    value: value.resolveDependentType(
                        protocolDescriptor: protocolDescriptor,
                        bindings: bindings
                    ),
                    protocolName: protocolDescriptor.name
                )
            case .result(let success, let failure):
                return try .result(
                    success: success.resolveDependentType(
                        protocolDescriptor: protocolDescriptor,
                        bindings: bindings
                    ),
                    failure: failure.resolveDependentType(
                        protocolDescriptor: protocolDescriptor,
                        bindings: bindings
                    ),
                    protocolName: protocolDescriptor.name
                )
            case .selfType:
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolDescriptor.name,
                    reason: "Dynamic Self is supported only as a direct result, not inside a container value schema."
                )
        }
    }
}

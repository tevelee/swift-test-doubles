import InternalRuntimeContract

package func makeExplicitMethodDescriptor(
    schema: RuntimeExplicitRequirementSchema,
    index: Int,
    witnessIndex: Int,
    receiver: StubRequirementReceiver,
    protocolDescriptor: RuntimeProtocolDescriptor,
    bindings: AssociatedTypeBindings,
    containsAssociatedTypes: Bool
) throws -> MethodDescriptor {
    try validateInferredRequirementSignature(
        schema: schema,
        index: index,
        protocolDescriptor: protocolDescriptor,
        containsAssociatedTypes: containsAssociatedTypes
    )
    try validateExplicitMethodGenericParameterIndices(
        schema: schema,
        index: index,
        protocolDescriptor: protocolDescriptor
    )

    let resolvedTypedError: (type: Any.Type?, dependency: WitnessValueDependency)
    if let name = schema.typedErrorAssociatedTypeName {
        let binding = try bindings.binding(
            named: name,
            declaredBy: protocolDescriptor
        )
        guard binding.type is any Error.Type else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Associated typed error '\(name)' is bound to '\(runtimeTypeName(binding.type))', which does not conform to Error."
            )
        }
        resolvedTypedError = (binding.type, bindings.dependency(for: binding))
    } else {
        resolvedTypedError = (schema.typedErrorType, .independent)
    }

    return try MethodDescriptor(
        kind: StubRequirementKind(schema.kind),
        receiver: receiver,
        origin: .explicit,
        name: "requirement_\(index)",
        index: index,
        witnessIndex: witnessIndex,
        arguments: try schema.arguments.map {
            try resolveExplicitWitnessValue(
                $0,
                protocolDescriptor: protocolDescriptor,
                bindings: bindings,
                requirementIndex: index,
                isArgument: true
            )
        },
        result: try resolveExplicitWitnessValue(
            schema.result,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings,
            requirementIndex: index,
            isArgument: false
        ),
        protocolName: protocolDescriptor.name,
        typedErrorType: resolvedTypedError.type,
        typedErrorDependency: resolvedTypedError.dependency,
        selfIsClassConstrained: protocolUsesClassSelfConvention(protocolDescriptor),
        isThrowing: schema.isThrowing,
        isAsync: schema.isAsync,
        typedWitnessAdapterFactory: typedWitnessAdapterFactory(
            from: schema.typedWitnessAdapter
        )
    )
}

private func validateExplicitMethodGenericParameterIndices(
    schema: RuntimeExplicitRequirementSchema,
    index: Int,
    protocolDescriptor: RuntimeProtocolDescriptor
) throws {
    let indices = schema.arguments.compactMap { value -> Int? in
        guard case .methodGenericParameter(let index) = value.source else {
            return nil
        }
        return index
    }
    guard indices.isEmpty == false else { return }

    guard indices.allSatisfy({ $0 >= 0 }) else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(index) uses a negative requirement-level generic parameter index. Indices must start at 0."
        )
    }

    let uniqueIndices = Set(indices)
    guard uniqueIndices.allSatisfy({ $0 < uniqueIndices.count }) else {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(index) uses sparse requirement-level generic parameter indices. Indices must form a dense sequence starting at 0."
        )
    }
}

private func resolveExplicitWitnessValue(
    _ value: RuntimeExplicitRequirementSchema.Value,
    protocolDescriptor: RuntimeProtocolDescriptor,
    bindings: AssociatedTypeBindings,
    requirementIndex: Int,
    isArgument: Bool
) throws -> ResolvedWitnessValue {
    if case .selfType(let isOptional) = value.source {
        return .selfValue(
            isOptional: isOptional,
            ownership: value.ownership.map(WitnessArgumentOwnership.init)
        )
    }
    if case .methodGenericParameter(let index) = value.source {
        guard isArgument else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(requirementIndex) describes a result typed by the requirement's own generic parameter. Only arguments support this schema."
            )
        }
        guard value.ownership != .owned else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Requirement \(requirementIndex) consumes a requirement-level generic parameter. Ownership-aware generic metadata transport is not implemented."
            )
        }
        return ResolvedWitnessValue(
            type: Any.self,
            convention: .methodGenericParameter(index: index),
            dependency: .independent,
            ownership: value.ownership.map(WitnessArgumentOwnership.init)
        )
    }
    return .resolved(
        try resolveExplicitDependentType(
            value.source,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings
        ),
        ownership: value.ownership.map(WitnessArgumentOwnership.init)
    )
}

private func resolveExplicitDependentType(
    _ source: RuntimeExplicitRequirementSchema.Source,
    protocolDescriptor: RuntimeProtocolDescriptor,
    bindings: AssociatedTypeBindings
) throws -> ResolvedDependentType {
    switch source {
        case .concrete(let type):
            return ResolvedDependentType(type: type, dependency: .independent)
        case .associatedType(let name):
            return try bindings.resolvedAssociatedType(
                named: name,
                declaredBy: protocolDescriptor
            )
        case .optional(let wrapped):
            return try resolveExplicitDependentType(
                wrapped,
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            ).optional()
        case .array(let element):
            return try resolveExplicitDependentType(
                element,
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            ).array()
        case .set(let element):
            let resolved = try resolveExplicitDependentType(
                element,
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            )
            return try resolved.set(
                protocolName: protocolDescriptor.name,
                sourceDescription: runtimeTypeName(resolved.type)
            )
        case .dictionary(let key, let value):
            return try .dictionary(
                key: resolveExplicitDependentType(
                    key,
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ),
                value: resolveExplicitDependentType(
                    value,
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ),
                protocolName: protocolDescriptor.name
            )
        case .result(let success, let failure):
            return try .result(
                success: resolveExplicitDependentType(
                    success,
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ),
                failure: resolveExplicitDependentType(
                    failure,
                    protocolDescriptor: protocolDescriptor,
                    bindings: bindings
                ),
                protocolName: protocolDescriptor.name
            )
        case .selfType:
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "Dynamic Self is supported only as a direct result, not inside a container value schema."
            )
        case .methodGenericParameter:
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "A requirement-level generic parameter is supported only as a direct argument, not inside a container value schema."
            )
    }
}

private func validateInferredRequirementSignature(
    schema: RuntimeExplicitRequirementSchema,
    index: Int,
    protocolDescriptor: RuntimeProtocolDescriptor,
    containsAssociatedTypes: Bool
) throws {
    guard schema.inferredFromSignature else { return }
    if containsAssociatedTypes {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(index) uses `signatureOf:` in an existential containing associated types. Function conversion erases associated-type identity; describe this requirement with explicit `Requirement.Value` values."
        )
    }

    let values = schema.arguments + [schema.result]
    let containsErasedSelf = values.contains { value in
        guard case .concrete(let type) = value.source else { return false }
        return ObjectIdentifier(type) == ObjectIdentifier(schema.erasedSelfType)
    }
    let containsErasedOptionalSelf = values.contains { value in
        guard case .concrete(let type) = value.source else { return false }
        return ObjectIdentifier(type) == ObjectIdentifier(schema.erasedOptionalSelfType)
    }
    if containsErasedSelf || containsErasedOptionalSelf {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason:
                "Requirement \(index) uses `signatureOf:` with a protocol-existential "
                + "value that may represent dynamic `Self`. Function conversion erases "
                + "that distinction; describe this requirement with explicit "
                + "`Requirement.Value` values."
        )
    }

    if schema.typedErrorType != nil || schema.typedErrorAssociatedTypeName != nil,
        schema.kind != .method && schema.kind != .getter
    {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(index) uses `signatureOf:` with typed throws on a setter or initializer. That requirement shape is unsupported."
        )
    }
}

private func typedWitnessAdapterFactory(
    from token: RuntimeTypedWitnessAdapterToken?
) -> TypedWitnessAdapterFactory? {
    guard let token else { return nil }
    guard let source = token.payload(as: RuntimeTypedWitnessAdapterSource.self) else {
        preconditionFailure(
            "[TestDoubles] RuntimeTypedWitnessAdapterToken contains an unexpected payload."
        )
    }
    return TypedWitnessAdapterFactory(
        functionType: source.functionType,
        invocationType: source.invocationType,
        make: { endpoint, slot in
            guard let target = UnsafeRawPointer(bitPattern: source.entryPoint) else {
                preconditionFailure(
                    "[TestDoubles] A typed witness adapter has no entry point."
                )
            }
            return TypedWitnessAdapter(
                target: target,
                invocation: source.makeInvocation(endpoint, slot)
            )
        }
    )
}

extension StubRequirementKind {
    fileprivate init(_ kind: RuntimeRequirementKind) {
        switch kind {
            case .method: self = .method
            case .initializer: self = .initializer
            case .getter: self = .getter
            case .setter: self = .setter
        }
    }
}

extension WitnessArgumentOwnership {
    fileprivate init(_ ownership: RuntimeArgumentOwnership) {
        switch ownership {
            case .borrowed: self = .borrowed
            case .owned: self = .owned
        }
    }
}

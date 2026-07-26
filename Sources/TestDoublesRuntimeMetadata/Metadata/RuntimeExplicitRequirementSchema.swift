/// Source-level requirement data normalized for runtime metadata resolution.
///
/// The public target builds this request from its stable factories; all
/// dependent-type resolution and ABI descriptor construction remains here.
package struct RuntimeExplicitRequirementSchema: @unchecked Sendable {
    package struct Value: Sendable {
        package let source: Source
        package let ownership: WitnessArgumentOwnership?

        package init(
            source: Source,
            ownership: WitnessArgumentOwnership?
        ) {
            self.source = source
            self.ownership = ownership
        }
    }

    package indirect enum Source: Sendable {
        case concrete(Any.Type)
        case associatedType(String)
        case optional(Source)
        case array(Source)
        case set(Source)
        case dictionary(key: Source, value: Source)
        case result(success: Source, failure: Source)
        case selfType(isOptional: Bool)
    }

    package let kind: StubRequirementKind
    package let arguments: [Value]
    package let result: Value
    package let typedErrorType: Any.Type?
    package let typedErrorAssociatedTypeName: String?
    package let isThrowing: Bool
    package let isAsync: Bool
    package let typedWitnessAdapterFactory: TypedWitnessAdapterFactory?
    package let inferredFromSignature: Bool
    package let erasedSelfType: Any.Type
    package let erasedOptionalSelfType: Any.Type

    package init(
        kind: StubRequirementKind,
        arguments: [Value],
        result: Value,
        typedErrorType: Any.Type?,
        typedErrorAssociatedTypeName: String?,
        isThrowing: Bool,
        isAsync: Bool,
        typedWitnessAdapterFactory: TypedWitnessAdapterFactory?,
        inferredFromSignature: Bool,
        erasedSelfType: Any.Type,
        erasedOptionalSelfType: Any.Type
    ) {
        self.kind = kind
        self.arguments = arguments
        self.result = result
        self.typedErrorType = typedErrorType
        self.typedErrorAssociatedTypeName = typedErrorAssociatedTypeName
        self.isThrowing = isThrowing
        self.isAsync = isAsync
        self.typedWitnessAdapterFactory = typedWitnessAdapterFactory
        self.inferredFromSignature = inferredFromSignature
        self.erasedSelfType = erasedSelfType
        self.erasedOptionalSelfType = erasedOptionalSelfType
    }
}

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
        kind: schema.kind,
        receiver: receiver,
        origin: .explicit,
        name: "requirement_\(index)",
        index: index,
        witnessIndex: witnessIndex,
        arguments: try schema.arguments.map {
            try resolveExplicitWitnessValue(
                $0,
                protocolDescriptor: protocolDescriptor,
                bindings: bindings
            )
        },
        result: try resolveExplicitWitnessValue(
            schema.result,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings
        ),
        protocolName: protocolDescriptor.name,
        typedErrorType: resolvedTypedError.type,
        typedErrorDependency: resolvedTypedError.dependency,
        selfIsClassConstrained: protocolUsesClassSelfConvention(protocolDescriptor),
        isThrowing: schema.isThrowing,
        isAsync: schema.isAsync,
        typedWitnessAdapterFactory: schema.typedWitnessAdapterFactory
    )
}

private func resolveExplicitWitnessValue(
    _ value: RuntimeExplicitRequirementSchema.Value,
    protocolDescriptor: RuntimeProtocolDescriptor,
    bindings: AssociatedTypeBindings
) throws -> ResolvedWitnessValue {
    if case .selfType(let isOptional) = value.source {
        return .selfValue(isOptional: isOptional, ownership: value.ownership)
    }
    return .resolved(
        try resolveExplicitDependentType(
            value.source,
            protocolDescriptor: protocolDescriptor,
            bindings: bindings
        ),
        ownership: value.ownership
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
        schema.kind != .method
    {
        throw RuntimeConstructionError.unsupportedProtocolShape(
            protocolName: protocolDescriptor.name,
            reason: "Requirement \(index) uses `signatureOf:` with typed throws on an accessor. Typed-throwing accessors are unsupported."
        )
    }
}

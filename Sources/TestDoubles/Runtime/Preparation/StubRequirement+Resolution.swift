import TestDoublesRuntime

extension Stub.Requirement.Value {
    var runtimeValue: RuntimeExplicitRequirementSchema.Value {
        RuntimeExplicitRequirementSchema.Value(
            source: source.runtimeSource,
            ownership: ownership
        )
    }
}

extension Stub.Requirement.Value.Source {
    var runtimeSource: RuntimeExplicitRequirementSchema.Source {
        switch self {
            case .concrete(let type):
                .concrete(type)
            case .associatedType(let name):
                .associatedType(name)
            case .optional(let wrapped):
                .optional(wrapped.runtimeSource)
            case .array(let element):
                .array(element.runtimeSource)
            case .set(let element):
                .set(element.runtimeSource)
            case .dictionary(let key, let value):
                .dictionary(
                    key: key.runtimeSource,
                    value: value.runtimeSource
                )
            case .result(let success, let failure):
                .result(
                    success: success.runtimeSource,
                    failure: failure.runtimeSource
                )
            case .selfType(let isOptional):
                .selfType(isOptional: isOptional)
        }
    }
}

extension Stub.Requirement {
    var runtimeSchema: RuntimeExplicitRequirementSchema {
        RuntimeExplicitRequirementSchema(
            kind: kind,
            arguments: arguments.map(\.runtimeValue),
            result: result.runtimeValue,
            typedErrorType: typedErrorType,
            typedErrorAssociatedTypeName: typedErrorAssociatedTypeName,
            isThrowing: isThrowing,
            isAsync: isAsync,
            typedWitnessAdapterFactory: typedWitnessAdapterFactory,
            inferredFromSignature: inferredFromSignature,
            erasedSelfType: P.self,
            erasedOptionalSelfType: Optional<P>.self
        )
    }
}

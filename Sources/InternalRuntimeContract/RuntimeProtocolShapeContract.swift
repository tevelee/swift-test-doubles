/// A caller-supplied concrete binding for one associated type declaration.
/// Descriptor lookup and identity validation belong to the runtime target.
package struct RuntimeAssociatedTypeBindingRequest: @unchecked Sendable {
    package let declaringProtocol: Any.Type
    package let name: String
    package let type: Any.Type

    package init(
        declaringProtocol: Any.Type,
        name: String,
        type: Any.Type
    ) {
        self.declaringProtocol = declaringProtocol
        self.name = name
        self.type = type
    }
}

/// Source-level input for runtime protocol-shape preparation.
///
/// The contract deliberately excludes protocol descriptors, witness tables,
/// layouts, and other ABI metadata owned by `TestDoublesRuntime`.
package struct RuntimeProtocolShapeRequest: @unchecked Sendable {
    package let protocolType: Any.Type
    package let typeDescription: String
    package let callerAssociatedTypeBindings: [RuntimeAssociatedTypeBindingRequest]

    package init(
        protocolType: Any.Type,
        typeDescription: String,
        callerAssociatedTypeBindings: [RuntimeAssociatedTypeBindingRequest]
    ) {
        self.protocolType = protocolType
        self.typeDescription = typeDescription
        self.callerAssociatedTypeBindings = callerAssociatedTypeBindings
    }
}

/// Source-level selection of the requirements used to prepare a runtime
/// stub, resolved against the private protocol layout before dispatch slots
/// or witness metadata are read.
package enum RuntimeExplicitRequirementInput: @unchecked Sendable {
    case automatic
    case flat([RuntimeExplicitRequirementSchema])
    case grouped([RuntimeExplicitRequirementGroup])
}

/// Compiler-emitted evidence for one concrete result and effect combination
/// whose client transport cannot be reconstructed from runtime metadata.
package struct RuntimeCompilerResultTransportEvidence: @unchecked Sendable {
    package enum Transport: Hashable, Sendable {
        case direct
        case indirect
    }

    package let resultType: Any.Type
    package let transport: Transport
    package let isThrowing: Bool
    package let isAsync: Bool

    package init(
        resultType: Any.Type,
        transport: Transport,
        isThrowing: Bool,
        isAsync: Bool
    ) {
        self.resultType = resultType
        self.transport = transport
        self.isThrowing = isThrowing
        self.isAsync = isAsync
    }

    package func matches(
        resultType actualResultType: Any.Type,
        isThrowing actualIsThrowing: Bool,
        isAsync actualIsAsync: Bool
    ) -> Bool {
        ObjectIdentifier(resultType) == ObjectIdentifier(actualResultType)
            && isThrowing == actualIsThrowing
            && isAsync == actualIsAsync
    }
}

/// Compiler-emitted adapter metadata that automatic discovery may apply when
/// runtime result transport is ambiguous.
///
/// An exact `argumentTypes` list carries a typed witness adapter. A `nil` list
/// proves only the result transport and lets an otherwise-supported method use
/// the ordinary argument trampoline.
package struct RuntimeAutomaticRequirementAdapter: @unchecked Sendable {
    package typealias ResultTransport = RuntimeCompilerResultTransportEvidence.Transport

    package let kind: RuntimeRequirementKind
    package let argumentTypes: [Any.Type]?
    package let resultTransportEvidence: RuntimeCompilerResultTransportEvidence
    package let typedWitnessAdapter: RuntimeTypedWitnessAdapterToken?

    package var resultType: Any.Type { resultTransportEvidence.resultType }
    package var resultTransport: ResultTransport { resultTransportEvidence.transport }
    package var isThrowing: Bool { resultTransportEvidence.isThrowing }
    package var isAsync: Bool { resultTransportEvidence.isAsync }

    package init(
        kind: RuntimeRequirementKind,
        argumentTypes: [Any.Type],
        resultType: Any.Type,
        resultTransport: ResultTransport,
        isThrowing: Bool,
        isAsync: Bool,
        typedWitnessAdapter: RuntimeTypedWitnessAdapterToken
    ) {
        self.kind = kind
        self.argumentTypes = argumentTypes
        resultTransportEvidence = RuntimeCompilerResultTransportEvidence(
            resultType: resultType,
            transport: resultTransport,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
        self.typedWitnessAdapter = typedWitnessAdapter
    }

    package init(
        kind: RuntimeRequirementKind,
        resultType: Any.Type,
        resultTransport: ResultTransport,
        isThrowing: Bool,
        isAsync: Bool
    ) {
        self.kind = kind
        argumentTypes = nil
        resultTransportEvidence = RuntimeCompilerResultTransportEvidence(
            resultType: resultType,
            transport: resultTransport,
            isThrowing: isThrowing,
            isAsync: isAsync
        )
        typedWitnessAdapter = nil
    }

    package func matches(argumentTypes actualArgumentTypes: [Any.Type]) -> Bool {
        guard let argumentTypes else { return true }
        return argumentTypes.count == actualArgumentTypes.count
            && zip(argumentTypes, actualArgumentTypes).allSatisfy {
                ObjectIdentifier($0.0) == ObjectIdentifier($0.1)
            }
    }
}

/// Explicit requirement schemas supplied for one declaring protocol.
package struct RuntimeExplicitRequirementGroup: @unchecked Sendable {
    package let declaringProtocol: Any.Type
    package let requirements: [RuntimeExplicitRequirementSchema]

    package init(
        declaringProtocol: Any.Type,
        requirements: [RuntimeExplicitRequirementSchema]
    ) {
        self.declaringProtocol = declaringProtocol
        self.requirements = requirements
    }
}

/// Source-level throwing-effect hints for automatically discovered getters.
package enum RuntimeGetterEffectInput: Sendable {
    case automatic
    case flat([RuntimeGetterEffectHint])
    case grouped([RuntimeGetterEffectGroup])
}

/// The complete caller-supplied throwing convention for one getter.
package struct RuntimeGetterEffectHint: @unchecked Sendable {
    package let isThrowing: Bool
    package let typedErrorType: Any.Type?

    package init(
        isThrowing: Bool,
        typedErrorType: Any.Type? = nil
    ) {
        self.isThrowing = isThrowing
        self.typedErrorType = typedErrorType
    }
}

/// Getter-effect hints supplied for one declaring protocol.
package struct RuntimeGetterEffectGroup: @unchecked Sendable {
    package let declaringProtocol: Any.Type
    package let effects: [RuntimeGetterEffectHint]

    package init(
        declaringProtocol: Any.Type,
        effects: [RuntimeGetterEffectHint]
    ) {
        self.declaringProtocol = declaringProtocol
        self.effects = effects
    }
}

/// The complete source-level input to runtime stub preparation. Free of
/// layouts, descriptors, witness tables, and ABI transport plans.
package struct RuntimeStubPreparationRequest: @unchecked Sendable {
    package let shape: RuntimeProtocolShapeRequest
    package let requirements: RuntimeExplicitRequirementInput
    package let getterEffects: RuntimeGetterEffectInput
    package let automaticRequirementAdapters: [RuntimeAutomaticRequirementAdapter]

    package init(
        shape: RuntimeProtocolShapeRequest,
        requirements: RuntimeExplicitRequirementInput,
        getterEffects: RuntimeGetterEffectInput,
        automaticRequirementAdapters: [RuntimeAutomaticRequirementAdapter]
    ) {
        self.shape = shape
        self.requirements = requirements
        self.getterEffects = getterEffects
        self.automaticRequirementAdapters = automaticRequirementAdapters
    }
}

/// A presentation-ready description of one dummy invocation failure.
///
/// The runtime owns the underlying witness coordinate; the semantic layer
/// receives only the stable dispatch slot and diagnostic wording.
package struct RuntimeDummyRequirement: Sendable {
    package let slot: Int
    package let description: String

    package init(slot: Int, description: String) {
        self.slot = slot
        self.description = description
    }
}

/// A caller-supplied concrete binding for one associated type declaration.
///
/// The declaring protocol metatype, associated-type name, and concrete type
/// are source-level values. Descriptor lookup and identity validation belong
/// to the runtime target.
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

/// Source-level selection of the requirements used to prepare a runtime stub.
///
/// Explicit schemas and declaring protocol metatypes are semantic inputs. The
/// runtime resolves them against its private protocol layout before it assigns
/// dispatch slots or reads witness metadata.
package enum RuntimeExplicitRequirementInput: @unchecked Sendable {
    case automatic
    case flat([RuntimeExplicitRequirementSchema])
    case grouped([RuntimeExplicitRequirementGroup])
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
    case flat([Bool])
    case grouped([RuntimeGetterEffectGroup])
}

/// Getter-effect hints supplied for one declaring protocol.
package struct RuntimeGetterEffectGroup: @unchecked Sendable {
    package let declaringProtocol: Any.Type
    package let effects: [Bool]

    package init(
        declaringProtocol: Any.Type,
        effects: [Bool]
    ) {
        self.declaringProtocol = declaringProtocol
        self.effects = effects
    }
}

/// The complete source-level input to runtime stub preparation.
///
/// This is intentionally free of layouts, descriptors, witness tables, and
/// ABI transport plans. Runtime preparation returns only semantic methods and
/// an opaque materialization plan to the public layer.
package struct RuntimeStubPreparationRequest: @unchecked Sendable {
    package let shape: RuntimeProtocolShapeRequest
    package let requirements: RuntimeExplicitRequirementInput
    package let getterEffects: RuntimeGetterEffectInput

    package init(
        shape: RuntimeProtocolShapeRequest,
        requirements: RuntimeExplicitRequirementInput,
        getterEffects: RuntimeGetterEffectInput
    ) {
        self.shape = shape
        self.requirements = requirements
        self.getterEffects = getterEffects
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

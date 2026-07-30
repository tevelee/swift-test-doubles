/// Concrete metadata paired with the source-level associated-type positions
/// that produced it.
package struct ResolvedDependentType: Sendable {
    package let type: Any.Type
    package let dependency: WitnessValueDependency

    package init(type: Any.Type, dependency: WitnessValueDependency) {
        self.type = type
        self.dependency = dependency
    }

    package func optional() -> Self {
        Self(
            type: _openExistential(type, do: optionalType),
            dependency: .optional(dependency)
        )
    }

    package func array() -> Self {
        Self(
            type: _openExistential(type, do: arrayType),
            dependency: .array(dependency)
        )
    }

    package func metatype() -> Self {
        func type<Instance>(of _: Instance.Type) -> Any.Type {
            Instance.Type.self
        }
        return Self(
            type: _openExistential(self.type, do: type),
            dependency: .metatype(dependency)
        )
    }

    package func set(
        protocolName: String,
        sourceDescription: String
    ) throws -> Self {
        guard let type = setType(of: type) else {
            let reason: String
            if let name = dependency.directAssociatedTypeName {
                reason =
                    "Associated type '\(name)' is used as a Set element, but "
                    + "its concrete binding '\(runtimeTypeName(self.type))' does "
                    + "not conform to Hashable. Bind '\(name)' to a Hashable "
                    + "concrete type."
            } else {
                reason =
                    "Set element '\(sourceDescription)' resolves to "
                    + "'\(runtimeTypeName(self.type))', which does not conform "
                    + "to Hashable."
            }
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
        return Self(type: type, dependency: .set(dependency))
    }

    package static func dictionary(
        key: Self,
        value: Self,
        protocolName: String
    ) throws -> Self {
        guard let type = dictionaryType(key: key.type, value: value.type) else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Dictionary key '\(runtimeTypeName(key.type))' does not conform to Hashable. Bind its associated type to a Hashable concrete type."
            )
        }
        return Self(
            type: type,
            dependency: .dictionary(
                key: key.dependency,
                value: value.dependency
            )
        )
    }

    package static func result(
        success: Self,
        failure: Self,
        protocolName: String
    ) throws -> Self {
        guard
            let type = resultType(
                success: success.type,
                failure: failure.type
            )
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Result failure '\(runtimeTypeName(failure.type))' does not conform to Error."
            )
        }
        return Self(
            type: type,
            dependency: .result(
                success: success.dependency,
                failure: failure.dependency
            )
        )
    }
}

/// A value resolved from either an explicit requirement or an automatically
/// discovered witness signature before its ABI layout is classified.
package struct ResolvedWitnessValue: Sendable {
    package let type: Any.Type
    package let convention: WitnessValueConvention
    package let dependency: WitnessValueDependency
    package let ownership: WitnessArgumentOwnership?

    package init(
        type: Any.Type,
        convention: WitnessValueConvention,
        dependency: WitnessValueDependency,
        ownership: WitnessArgumentOwnership?
    ) {
        self.type = type
        self.convention = convention
        self.dependency = dependency
        self.ownership = ownership
    }

    package func argumentOwnership(
        for kind: StubRequirementKind,
        at offset: Int
    ) -> WitnessArgumentOwnership {
        ownership ?? kind.defaultArgumentOwnership(at: offset)
    }

    package static func resolved(
        _ value: ResolvedDependentType,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        let convention: WitnessValueConvention
        if value.dependency.usesOpaqueValueWitnessConvention,
            let name = value.dependency.firstAssociatedTypeName
        {
            convention = .associatedType(name: name)
        } else {
            convention = .concrete
        }
        return Self(
            type: value.type,
            convention: convention,
            dependency: value.dependency,
            ownership: ownership
        )
    }

    /// The dynamic `Self` value transported through fabricated payload storage.
    package static func selfValue(
        isOptional: Bool,
        isInout: Bool = false,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        precondition(isInout == false || isOptional == false)
        return Self(
            type: isOptional ? Optional<FabricatedPayload>.self : FabricatedPayload.self,
            convention:
                isInout
                ? .inoutSelf
                : (isOptional ? .optionalSelf : .selfType),
            dependency: .independent,
            ownership: ownership
        )
    }
}

/// Concrete metadata paired with the source-level associated-type positions
/// that produced it.
struct ResolvedDependentType: Sendable {
    let type: Any.Type
    let dependency: WitnessValueDependency

    func optional() -> Self {
        Self(
            type: _openExistential(type, do: optionalType),
            dependency: .optional(dependency)
        )
    }

    func array() -> Self {
        Self(
            type: _openExistential(type, do: arrayType),
            dependency: .array(dependency)
        )
    }

    func set(
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
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
        return Self(type: type, dependency: .set(dependency))
    }

    static func dictionary(
        key: Self,
        value: Self,
        protocolName: String
    ) throws -> Self {
        guard let type = dictionaryType(key: key.type, value: value.type) else {
            throw StubError.unsupportedProtocolShape(
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

    static func result(
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
            throw StubError.unsupportedProtocolShape(
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
struct ResolvedWitnessValue: Sendable {
    let type: Any.Type
    let convention: WitnessValueConvention
    let dependency: WitnessValueDependency
    let ownership: WitnessArgumentOwnership?

    func argumentOwnership(
        for kind: StubRequirementKind,
        at offset: Int
    ) -> WitnessArgumentOwnership {
        ownership ?? kind.defaultArgumentOwnership(at: offset)
    }

    static func resolved(
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

    /// The dynamic `Self` value transported through `StubPayload` storage.
    static func selfValue(
        isOptional: Bool,
        ownership: WitnessArgumentOwnership? = nil
    ) -> Self {
        Self(
            type: isOptional ? Optional<StubPayload>.self : StubPayload.self,
            convention: isOptional ? .optionalSelf : .selfType,
            dependency: .independent,
            ownership: ownership
        )
    }
}

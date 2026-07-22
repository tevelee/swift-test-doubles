/// One associated-type occurrence in a protocol requirement signature.
///
/// Resolved occurrences retain the declaring protocol as part of their
/// identity. Name-only occurrences exist solely for low-level synthetic
/// descriptors that have no declaring protocol context.
enum AssociatedTypeReference: Equatable, Sendable {
    case declaration(AssociatedTypeID)
    /// An exact associated-type declaration whose `AnyObject` constraint
    /// fixes its formal witness transport to one reference word.
    case referenceDeclaration(AssociatedTypeID)
    case name(String)

    var name: String {
        switch self {
            case .declaration(let id), .referenceDeclaration(let id): id.name
            case .name(let name): name
        }
    }

    var usesReferenceABI: Bool {
        if case .referenceDeclaration = self { return true }
        return false
    }
}

/// The structural positions at which a witness value depends on associated
/// metadata.
///
/// Keeping the complete source shape prevents equal concrete substitutions
/// from erasing either generic-argument positions or declaring-protocol
/// identity during explicit requirement validation.
indirect enum WitnessValueDependency: Equatable, Sendable {
    case independent
    case associatedType(AssociatedTypeReference)
    case optional(WitnessValueDependency)
    case array(WitnessValueDependency)
    case set(WitnessValueDependency)
    case dictionary(
        key: WitnessValueDependency,
        value: WitnessValueDependency
    )
    case result(
        success: WitnessValueDependency,
        failure: WitnessValueDependency
    )
    case genericClass(
        constructor: GenericClassID,
        arguments: [WitnessValueDependency]
    )

    /// Compatibility construction for synthetic descriptors and focused
    /// descriptor tests that have no declaring protocol metadata.
    static func associatedType(name: String) -> Self {
        .associatedType(.name(name))
    }

    static func associatedType(id: AssociatedTypeID) -> Self {
        .associatedType(.declaration(id))
    }

    static func referenceAssociatedType(id: AssociatedTypeID) -> Self {
        .associatedType(.referenceDeclaration(id))
    }

    /// Compatibility construction for the previously flat Dictionary marker.
    static func dictionary(key: String?, value: String?) -> Self {
        .dictionary(
            key: key.map(Self.associatedType(name:)) ?? .independent,
            value: value.map(Self.associatedType(name:)) ?? .independent
        )
    }

    var isAssociatedTypeDependent: Bool {
        switch self {
            case .independent:
                false
            case .associatedType:
                true
            case .optional(let wrapped), .array(let wrapped), .set(let wrapped):
                wrapped.isAssociatedTypeDependent
            case .dictionary(let key, let value):
                key.isAssociatedTypeDependent || value.isAssociatedTypeDependent
            case .result(let success, let failure):
                success.isAssociatedTypeDependent
                    || failure.isAssociatedTypeDependent
            case .genericClass(_, let arguments):
                arguments.contains(where: \.isAssociatedTypeDependent)
        }
    }

    /// Whether Swift's formal generic witness convention transports the
    /// complete value indirectly.
    ///
    /// The decision follows the source-level generic shape, not the value
    /// witnesses of a concrete substitution. Standard-library collection
    /// shells have fixed reference-backed layouts, while Optional preserves
    /// whether its wrapped value is formally opaque.
    var usesOpaqueValueWitnessConvention: Bool {
        switch self {
            case .independent:
                false
            case .associatedType(let reference):
                reference.usesReferenceABI == false
            case .optional(let wrapped):
                wrapped.usesOpaqueValueWitnessConvention
            case .array, .set, .dictionary:
                false
            case .result(let success, let failure):
                success.usesOpaqueValueWitnessConvention
                    || failure.usesOpaqueValueWitnessConvention
            case .genericClass:
                false
        }
    }

    var firstAssociatedTypeName: String? {
        switch self {
            case .independent:
                nil
            case .associatedType(let reference):
                reference.name
            case .optional(let wrapped), .array(let wrapped), .set(let wrapped):
                wrapped.firstAssociatedTypeName
            case .dictionary(let key, let value):
                key.firstAssociatedTypeName ?? value.firstAssociatedTypeName
            case .result(let success, let failure):
                success.firstAssociatedTypeName
                    ?? failure.firstAssociatedTypeName
            case .genericClass(_, let arguments):
                arguments.lazy.compactMap(\.firstAssociatedTypeName).first
        }
    }

    var directAssociatedTypeName: String? {
        guard case .associatedType(let reference) = self else { return nil }
        return reference.name
    }

    var containsReferenceAssociatedType: Bool {
        switch self {
            case .independent:
                false
            case .associatedType(let reference):
                reference.usesReferenceABI
            case .optional(let wrapped), .array(let wrapped), .set(let wrapped):
                wrapped.containsReferenceAssociatedType
            case .dictionary(let key, let value):
                key.containsReferenceAssociatedType
                    || value.containsReferenceAssociatedType
            case .result(let success, let failure):
                success.containsReferenceAssociatedType
                    || failure.containsReferenceAssociatedType
            case .genericClass(_, let arguments):
                arguments.contains(where: \.containsReferenceAssociatedType)
        }
    }

    /// The new reference-associated slice accepts only the direct occurrence
    /// and exactly one Optional shell. Other dependent outer shapes keep their
    /// existing fail-closed boundary until their constrained formal ABI is
    /// probed independently.
    var usesSupportedReferenceAssociatedTransport: Bool {
        guard containsReferenceAssociatedType else { return true }
        switch self {
            case .associatedType(let reference):
                return reference.usesReferenceABI
            case .optional(.associatedType(let reference)):
                return reference.usesReferenceABI
            default:
                return false
        }
    }

    /// Preserves the existing name-based descriptor projections while exact
    /// structural dependencies remain stored on each witness value.
    var legacyProjection: Self {
        switch self {
            case .independent:
                .independent
            case .associatedType(let reference):
                .associatedType(name: reference.name)
            case .optional(let wrapped), .array(let wrapped), .set(let wrapped):
                wrapped.legacyProjection
            case .dictionary(let key, let value):
                .dictionary(
                    key: key.legacyProjection,
                    value: value.legacyProjection
                )
            case .result(let success, let failure):
                .result(
                    success: success.legacyProjection,
                    failure: failure.legacyProjection
                )
            case .genericClass(let constructor, let arguments):
                .genericClass(
                    constructor: constructor,
                    arguments: arguments.map(\.legacyProjection)
                )
        }
    }
}

// AssociatedTypeID is a pair of an immutable descriptor address and a name.
// The address is used only as stable process-local identity.
extension AssociatedTypeID: @unchecked Sendable {}

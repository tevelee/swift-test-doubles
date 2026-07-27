import Echo

/// Swift encodes `ProtocolClassConstraint.class` as zero and `.any` as one.
/// Echo 0.0.5's `hasClassConstraint` projection exposes the raw bit instead of
/// the semantic answer, so classify the declaring protocol from the ABI bit.
package func protocolUsesClassSelfConvention(
    _ descriptor: ProtocolDescriptor
) -> Bool {
    descriptor.protocolFlags.bits & 0x1 == 0
}

package enum StubRequirementKind: String, Hashable, Sendable {
    case method
    case initializer
    case getter
    case setter

    package init?(_ kind: ProtocolRequirement.Kind) {
        switch kind {
            case .method:
                self = .method
            case .`init`:
                self = .initializer
            case .getter:
                self = .getter
            case .setter:
                self = .setter
            default:
                return nil
        }
    }

    package func defaultArgumentOwnership(at offset: Int) -> WitnessArgumentOwnership {
        switch self {
            case .setter:
                offset == 0 ? .owned : .borrowed
            case .initializer:
                .owned
            case .method, .getter:
                .borrowed
        }
    }
}

package enum StubRequirementReceiver: String, Sendable {
    case instance
    case metatype
}

package enum WitnessValueConvention: Equatable, Sendable {
    case concrete
    case associatedType(name: String)
    case selfType
    case optionalSelf
    /// Typed by the requirement's own generic parameter; `index` identifies
    /// which one, so shared parameters share an index.
    case methodGenericParameter(index: Int)
}

package enum WitnessArgumentOwnership: String, Equatable, Sendable {
    case borrowed
    case owned
}

/// The runtime type, semantic convention, dependency, and ABI transport for
/// one value in a protocol witness call.
package struct WitnessValueDescriptor: Sendable {
    package let type: Any.Type
    package let convention: WitnessValueConvention
    package let dependency: WitnessValueDependency
    package let layout: ABIClass
}

/// An incoming witness value and the ownership convention applied after it is
/// decoded from the call frame.
package struct WitnessArgumentDescriptor: Sendable {
    package let value: WitnessValueDescriptor
    package let ownership: WitnessArgumentOwnership
}

extension WitnessValueDescriptor {
    /// Whether both values describe the same runtime type, semantic
    /// convention, and dependency. ABI layout follows from those inputs.
    package func matches(_ other: Self) -> Bool {
        sameType(type, other.type)
            && convention == other.convention
            && dependency == other.dependency
    }
}

extension WitnessArgumentDescriptor {
    package func matches(_ other: Self) -> Bool {
        value.matches(other.value) && ownership == other.ownership
    }
}

package func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}

private func sameType(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

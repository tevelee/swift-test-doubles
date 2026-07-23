import Echo

/// Swift encodes `ProtocolClassConstraint.class` as zero and `.any` as one.
/// Echo 0.0.5's `hasClassConstraint` projection exposes the raw bit instead of
/// the semantic answer, so classify the declaring protocol from the ABI bit.
func protocolUsesClassSelfConvention(
    _ descriptor: ProtocolDescriptor
) -> Bool {
    descriptor.protocolFlags.bits & 0x1 == 0
}

enum StubRequirementKind: String, Hashable, Sendable {
    case method
    case initializer
    case getter
    case setter

    init?(_ kind: ProtocolRequirement.Kind) {
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

    func defaultArgumentOwnership(at offset: Int) -> WitnessArgumentOwnership {
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

enum StubRequirementReceiver: String, Sendable {
    case instance
    case metatype
}

enum WitnessValueConvention: Equatable, Sendable {
    case concrete
    case associatedType(name: String)
    case selfType
    case optionalSelf
}

enum WitnessArgumentOwnership: String, Equatable, Sendable {
    case borrowed
    case owned
}

/// The runtime type, semantic convention, dependency, and ABI transport for
/// one value in a protocol witness call.
struct WitnessValueDescriptor: Sendable {
    let type: Any.Type
    let convention: WitnessValueConvention
    let dependency: WitnessValueDependency
    let layout: ABIClass
}

/// An incoming witness value and the ownership convention applied after it is
/// decoded from the call frame.
struct WitnessArgumentDescriptor: Sendable {
    let value: WitnessValueDescriptor
    let ownership: WitnessArgumentOwnership
}

extension WitnessValueDescriptor {
    /// Whether both values describe the same runtime type, semantic
    /// convention, and dependency. ABI layout follows from those inputs.
    func matches(_ other: Self) -> Bool {
        sameType(type, other.type)
            && convention == other.convention
            && dependency == other.dependency
    }
}

extension WitnessArgumentDescriptor {
    func matches(_ other: Self) -> Bool {
        value.matches(other.value) && ownership == other.ownership
    }
}

func runtimeTypeName(_ type: Any.Type) -> String {
    type == Void.self ? "Swift.Void" : String(reflecting: type)
}

private func sameType(_ lhs: Any.Type, _ rhs: Any.Type) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

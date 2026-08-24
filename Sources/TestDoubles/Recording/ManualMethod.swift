import InternalRuntimeContract

/// Opaque recorder key used only by source-level `CompiledStub` forwarding.
///
/// The manual path deliberately never exposes or inspects a witness ABI
/// descriptor. The recorder unwraps this token at its semantic boundary.
struct ManualMethod {
    let descriptor: RuntimeMethod

    var index: Int { descriptor.index }
    var name: String { descriptor.name }
}

enum ManualMethodKind {
    case method
    case getter
    case setter

    var runtimeKind: RuntimeRequirementKind {
        switch self {
            case .method: .method
            case .getter: .getter
            case .setter: .setter
        }
    }
}

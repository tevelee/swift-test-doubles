enum StubExistentialRepresentation {
    case opaque
    case classConstrained
    case superclassConstrained(Any.Type)

    var isClassConstrained: Bool {
        switch self {
            case .opaque: false
            case .classConstrained, .superclassConstrained: true
        }
    }
}

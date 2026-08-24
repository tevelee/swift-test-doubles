package enum StubExistentialRepresentation {
    case opaque
    case classConstrained
    case superclassConstrained(Any.Type)

    package var isClassConstrained: Bool {
        switch self {
            case .opaque: false
            case .classConstrained, .superclassConstrained: true
        }
    }
}

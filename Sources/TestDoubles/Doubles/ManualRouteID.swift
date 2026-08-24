struct ManualRouteID: Hashable, Sendable {
    let signature: String
    let argumentTypeIDs: [ObjectIdentifier]

    init(_ signature: String, argumentTypeIDs: [ObjectIdentifier]) {
        self.signature = signature
        self.argumentTypeIDs = argumentTypeIDs
    }
}

enum ManualMethodRouteIdentity: Hashable, Sendable {
    case implicit(String)
    case typed(ManualRouteID)

    var signature: String {
        switch self {
            case .implicit(let signature):
                signature
            case .typed(let route):
                route.signature
        }
    }
}

struct ManualPackedArguments {
    let values: [Any]
    let typeIDs: [ObjectIdentifier]

    func route(for signature: String) -> ManualMethodRouteIdentity {
        typeIDs.isEmpty
            ? .implicit(signature)
            : .typed(
                ManualRouteID(
                    signature,
                    argumentTypeIDs: typeIDs
                )
            )
    }
}

func manualPackedArguments<each Argument>(
    _ arguments: repeat each Argument
) -> ManualPackedArguments {
    var values: [Any] = []
    var typeIDs: [ObjectIdentifier] = []
    for argument in repeat each arguments {
        values.append(argument)
    }
    for type in repeat (each Argument).self {
        typeIDs.append(ObjectIdentifier(type))
    }
    return ManualPackedArguments(values: values, typeIDs: typeIDs)
}

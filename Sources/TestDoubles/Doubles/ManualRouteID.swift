/// Identifies a manually forwarded requirement whose printed signature is not
/// sufficient to distinguish it from another overload.
///
/// Older manually generated conformers used this explicit route to distinguish
/// argument-type overloads:
///
/// ```swift
/// func render(_ value: Int) -> String {
///     stub.call(
///         value,
///         route: ManualRouteID(argumentTypes: Int.self)
///     )
/// }
/// ```
///
/// New conformers should call `stub.call(value)` directly. Parameter-pack
/// forwarding now preserves static argument types automatically. This type
/// remains available for source compatibility with existing conformers.
public struct ManualRouteID: Hashable, Sendable {
    let signature: String
    let argumentTypeIDs: [ObjectIdentifier]

    /// Creates a typed route for a manually forwarded requirement.
    ///
    /// - Parameters:
    ///   - signature: The diagnostic signature and base route name. Its default
    ///     is the forwarding requirement's `#function` value.
    ///   - argumentTypes: The requirement's static argument types, in declaration
    ///     order.
    @available(
        *,
        deprecated,
        message: "ManualStub.call now preserves argument types automatically."
    )
    public init(
        _ signature: String = #function,
        argumentTypes: Any.Type...
    ) {
        self.signature = signature
        self.argumentTypeIDs = argumentTypes.map(ObjectIdentifier.init)
    }

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

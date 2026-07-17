/// Identifies a manually forwarded requirement whose printed signature is not
/// sufficient to distinguish it from another overload.
///
/// Use a typed route from a ``ManualStub`` explicit fallback when requirements
/// have the same argument labels, result type, and effects but different
/// argument types:
///
/// ```swift
/// func render(_ value: Int) -> String {
///     stub.call(value, route: ManualRouteID(argumentTypes: Int.self))
/// }
/// ```
///
/// The default signature is evaluated in the forwarding requirement, just like
/// the string-based fallback's `#function` default. Argument types participate
/// only in route identity; diagnostics continue to show the readable signature.
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
    public init(
        _ signature: String = #function,
        argumentTypes: Any.Type...
    ) {
        self.signature = signature
        self.argumentTypeIDs = argumentTypes.map(ObjectIdentifier.init)
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

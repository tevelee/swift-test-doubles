/// A caller-supplied concrete binding for one associated type declaration.
///
/// The declaring protocol metatype, associated-type name, and concrete type
/// are source-level values. Descriptor lookup and identity validation belong
/// to the runtime target.
package struct RuntimeAssociatedTypeBindingRequest: @unchecked Sendable {
    package let declaringProtocol: Any.Type
    package let name: String
    package let type: Any.Type

    package init(
        declaringProtocol: Any.Type,
        name: String,
        type: Any.Type
    ) {
        self.declaringProtocol = declaringProtocol
        self.name = name
        self.type = type
    }
}

/// Source-level input for runtime protocol-shape preparation.
///
/// The contract deliberately excludes protocol descriptors, witness tables,
/// layouts, and other ABI metadata owned by `TestDoublesRuntime`.
package struct RuntimeProtocolShapeRequest: @unchecked Sendable {
    package let protocolType: Any.Type
    package let typeDescription: String
    package let callerAssociatedTypeBindings: [RuntimeAssociatedTypeBindingRequest]

    package init(
        protocolType: Any.Type,
        typeDescription: String,
        callerAssociatedTypeBindings: [RuntimeAssociatedTypeBindingRequest]
    ) {
        self.protocolType = protocolType
        self.typeDescription = typeDescription
        self.callerAssociatedTypeBindings = callerAssociatedTypeBindings
    }
}

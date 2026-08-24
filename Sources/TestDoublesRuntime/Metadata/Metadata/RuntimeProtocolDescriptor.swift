import Echo

/// An opaque protocol-descriptor identity for the semantic target.
///
/// The wrapper deliberately keeps Echo's metadata wrapper within the runtime
/// target while still allowing the public target to name protocol groups and
/// associated-type bindings by their source-level protocol metatype.
package struct RuntimeProtocolDescriptor: @unchecked Sendable {
    let raw: ProtocolDescriptor

    package let name: String

    init(_ raw: ProtocolDescriptor) {
        self.raw = raw
        name = raw.name
    }
}

package func runtimeSingleProtocolDescriptor(
    of type: Any.Type
) -> RuntimeProtocolDescriptor? {
    guard let existential = reflect(type) as? ExistentialMetadata,
        existential.protocols.count == 1
    else {
        return nil
    }
    return RuntimeProtocolDescriptor(existential.protocols[0])
}

package func protocolUsesClassSelfConvention(
    _ descriptor: RuntimeProtocolDescriptor
) -> Bool {
    protocolUsesClassSelfConvention(descriptor.raw)
}

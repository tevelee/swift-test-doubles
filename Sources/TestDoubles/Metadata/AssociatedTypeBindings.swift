import Echo

/// Stable identity for one associated type declared by a protocol descriptor.
///
/// Associated-type names are scoped to their declaring protocol, so the name
/// alone is not sufficient in inheritance graphs and protocol compositions.
struct AssociatedTypeID: Hashable {
    let protocolID: ProtocolLayout.DescriptorID
    let name: String

    init(protocolDescriptor: ProtocolDescriptor, name: String) {
        protocolID = ProtocolLayout.DescriptorID(protocolDescriptor)
        self.name = name
    }
}

/// Concrete associated-type bindings with deterministic metadata order and
/// indexed lookup by declaration identity.
struct AssociatedTypeBindings {
    let ordered: [StubProtocolMetadata.AssociatedTypeBinding]

    private let byID: [AssociatedTypeID: StubProtocolMetadata.AssociatedTypeBinding]
    private let byProtocolID: [ProtocolLayout.DescriptorID: [StubProtocolMetadata.AssociatedTypeBinding]]

    init() {
        self.init([])
    }

    init(_ bindings: [StubProtocolMetadata.AssociatedTypeBinding]) {
        ordered = bindings

        var byID: [AssociatedTypeID: StubProtocolMetadata.AssociatedTypeBinding] = [:]
        var byProtocolID: [ProtocolLayout.DescriptorID: [StubProtocolMetadata.AssociatedTypeBinding]] = [:]
        for binding in bindings {
            byID[binding.id] = binding
            byProtocolID[binding.id.protocolID, default: []].append(binding)
        }
        self.byID = byID
        self.byProtocolID = byProtocolID
    }

    var isEmpty: Bool { ordered.isEmpty }
    var count: Int { ordered.count }
    var ids: [AssociatedTypeID] { ordered.map(\.id) }
    var hasUniqueIDs: Bool { byID.count == ordered.count }

    subscript(id: AssociatedTypeID) -> StubProtocolMetadata.AssociatedTypeBinding? {
        byID[id]
    }

    func declared(
        by protocolDescriptor: ProtocolDescriptor
    ) -> [StubProtocolMetadata.AssociatedTypeBinding] {
        byProtocolID[ProtocolLayout.DescriptorID(protocolDescriptor)] ?? []
    }

    /// Returns the concrete binding for one associated type, or throws the
    /// shared unbound-associated-type diagnostic.
    func binding(
        named name: String,
        declaredBy protocolDescriptor: ProtocolDescriptor
    ) throws -> StubProtocolMetadata.AssociatedTypeBinding {
        let id = AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
        guard let binding = self[id] else {
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "No concrete binding is available for associated type '\(name)'. Construct the stub as `Stub<any \(protocolDescriptor.name)<ConcreteType>>`."
            )
        }
        return binding
    }
}

extension StubProtocolMetadata.AssociatedTypeBinding {
    var id: AssociatedTypeID {
        AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
    }
}

extension ProtocolLayout.AssociatedTypeRequirement {
    var id: AssociatedTypeID {
        AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
    }
}

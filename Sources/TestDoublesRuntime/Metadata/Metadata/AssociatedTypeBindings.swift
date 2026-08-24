import Echo

/// Stable identity for one associated type declared by a protocol descriptor.
///
/// Associated-type names are scoped to their declaring protocol, so the name
/// alone is not sufficient in inheritance graphs and protocol compositions.
package struct AssociatedTypeID: Hashable {
    package let protocolID: ProtocolLayout.DescriptorID
    package let name: String

    package init(protocolDescriptor: ProtocolDescriptor, name: String) {
        protocolID = ProtocolLayout.DescriptorID(protocolDescriptor)
        self.name = name
    }

    package init(protocolDescriptor: RuntimeProtocolDescriptor, name: String) {
        self.init(protocolDescriptor: protocolDescriptor.raw, name: name)
    }
}

/// Concrete associated-type bindings with deterministic metadata order and
/// indexed lookup by declaration identity.
package struct AssociatedTypeBindings {
    package let ordered: [StubProtocolMetadata.AssociatedTypeBinding]

    private let byID: [AssociatedTypeID: StubProtocolMetadata.AssociatedTypeBinding]
    private let byProtocolID: [ProtocolLayout.DescriptorID: [StubProtocolMetadata.AssociatedTypeBinding]]
    private let referenceAssociatedTypeIDs: Set<AssociatedTypeID>

    package init() {
        self.init([])
    }

    package init(
        _ bindings: [StubProtocolMetadata.AssociatedTypeBinding],
        referenceAssociatedTypeIDs: Set<AssociatedTypeID> = []
    ) {
        ordered = bindings
        self.referenceAssociatedTypeIDs = referenceAssociatedTypeIDs

        var byID: [AssociatedTypeID: StubProtocolMetadata.AssociatedTypeBinding] = [:]
        var byProtocolID: [ProtocolLayout.DescriptorID: [StubProtocolMetadata.AssociatedTypeBinding]] = [:]
        for binding in bindings {
            byID[binding.id] = binding
            byProtocolID[binding.id.protocolID, default: []].append(binding)
        }
        self.byID = byID
        self.byProtocolID = byProtocolID
    }

    package var isEmpty: Bool { ordered.isEmpty }
    package var count: Int { ordered.count }
    package var ids: [AssociatedTypeID] { ordered.map(\.id) }
    package var hasUniqueIDs: Bool { byID.count == ordered.count }

    package subscript(id: AssociatedTypeID) -> StubProtocolMetadata.AssociatedTypeBinding? {
        byID[id]
    }

    package func declared(
        by protocolDescriptor: ProtocolDescriptor
    ) -> [StubProtocolMetadata.AssociatedTypeBinding] {
        byProtocolID[ProtocolLayout.DescriptorID(protocolDescriptor)] ?? []
    }

    package func declared(
        by protocolDescriptor: RuntimeProtocolDescriptor
    ) -> [StubProtocolMetadata.AssociatedTypeBinding] {
        declared(by: protocolDescriptor.raw)
    }

    /// Returns the concrete binding for one associated type, or throws the
    /// shared unbound-associated-type diagnostic.
    package func binding(
        named name: String,
        declaredBy protocolDescriptor: ProtocolDescriptor
    ) throws -> StubProtocolMetadata.AssociatedTypeBinding {
        let id = AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
        guard let binding = self[id] else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolDescriptor.name,
                reason: "No concrete binding is available for associated type '\(name)'. Construct the stub as `Stub<any \(protocolDescriptor.name)<ConcreteType>>`."
            )
        }
        return binding
    }

    package func binding(
        named name: String,
        declaredBy protocolDescriptor: RuntimeProtocolDescriptor
    ) throws -> StubProtocolMetadata.AssociatedTypeBinding {
        try binding(named: name, declaredBy: protocolDescriptor.raw)
    }

    package func dependency(
        for binding: StubProtocolMetadata.AssociatedTypeBinding
    ) -> WitnessValueDependency {
        if referenceAssociatedTypeIDs.contains(binding.id) {
            return .referenceAssociatedType(id: binding.id)
        }
        return .associatedType(id: binding.id)
    }

    package func resolvedAssociatedType(
        named name: String,
        declaredBy protocolDescriptor: ProtocolDescriptor
    ) throws -> ResolvedDependentType {
        let binding = try binding(
            named: name,
            declaredBy: protocolDescriptor
        )
        return ResolvedDependentType(
            type: binding.type,
            dependency: dependency(for: binding)
        )
    }

    package func resolvedAssociatedType(
        named name: String,
        declaredBy protocolDescriptor: RuntimeProtocolDescriptor
    ) throws -> ResolvedDependentType {
        try resolvedAssociatedType(named: name, declaredBy: protocolDescriptor.raw)
    }

    package func validateReferenceBindings() throws {
        for binding in ordered where referenceAssociatedTypeIDs.contains(binding.id) {
            guard binding.type is AnyObject.Type else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: binding.protocolDescriptor.name,
                    reason:
                        "AnyObject-constrained associated type '\(binding.name)' must be bound to a concrete class type. "
                        + "'\(runtimeTypeName(binding.type))' is a value type or class existential."
                )
            }
        }
    }
}

extension StubProtocolMetadata.AssociatedTypeBinding {
    package var id: AssociatedTypeID {
        AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
    }
}

extension ProtocolLayout.AssociatedTypeRequirement {
    package var id: AssociatedTypeID {
        AssociatedTypeID(protocolDescriptor: protocolDescriptor, name: name)
    }
}

import Echo
#if canImport(ObjectiveC)
    import Foundation
#endif

extension Stub {
    /// A concrete runtime binding for an associated type of an unbound protocol existential.
    public struct AssociatedTypeBinding: Sendable {
        let protocolType: Any.Type
        let name: String
        let type: Any.Type

        /// Binds one associated type declared by `protocolType` to `type`.
        ///
        /// The declaring protocol is part of the binding identity, so
        /// compositions may bind equally named associated types independently.
        public static func binding(
            declaredBy protocolType: Any.Type,
            named name: String,
            to type: Any.Type
        ) -> Self {
            Self(protocolType: protocolType, name: name, type: type)
        }
    }
}

extension Stub {
    static func extractProtocolShape(
        callerAssociatedTypeBindings: [AssociatedTypeBinding] = []
    ) throws -> StubProtocolShape {
        let typeDescription = String(reflecting: P.self)
        let metadata = try inspectStubProtocolMetadata(
            P.self,
            typeDescription: typeDescription
        )
        guard metadata.protocols.isEmpty == false else {
            throw StubError.typeIsNotProtocol(typeDescription: typeDescription)
        }
        let roots = metadata.protocols
        guard metadata.specialProtocol == .none,
            metadata.numberOfWitnessTables == roots.count
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: typeDescription,
                reason: "Only ordinary Swift opaque or class-constrained protocol existentials are supported."
            )
        }
        let representation: StubExistentialRepresentation
        if metadata.hasSuperclassConstraint {
            guard let superclass = metadata.superclass else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: "The superclass-constrained existential metadata does not contain a superclass type."
                )
            }
            #if canImport(ObjectiveC)
                guard superclass is NSObject.Type else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: typeDescription,
                        reason: "Superclass-constrained runtime test doubles require an NSObject-backed superclass so a genuine instance can own the fabricated runtime resources."
                    )
                }
                representation = .superclassConstrained(superclass)
            #else
                throw StubError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: "Superclass-constrained runtime test doubles require the Objective-C runtime and an NSObject-backed superclass."
                )
            #endif
        } else {
            representation = metadata.isClassConstrained ? .classConstrained : .opaque
        }
        let layout = try ProtocolLayout.build(
            roots: roots,
            allowsClassConstraint: representation.isClassConstrained
        )
        let associatedTypeRequirements = layout.associatedTypeRequirements
        let referenceAssociatedTypeIDs = Set(
            associatedTypeRequirements
                .filter(\.usesReferenceABI)
                .map(\.id)
        )
        let associatedTypeBindings: AssociatedTypeBindings
        if callerAssociatedTypeBindings.isEmpty {
            associatedTypeBindings = AssociatedTypeBindings(
                metadata.associatedTypeBindings,
                referenceAssociatedTypeIDs: referenceAssociatedTypeIDs
            )
        } else {
            guard metadata.associatedTypeBindings.isEmpty else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: typeDescription,
                    reason: "Caller-supplied associated-type bindings require an unbound protocol existential. Remove the bindings or construct the stub with an unbound `any Protocol` type."
                )
            }
            associatedTypeBindings = try resolveCallerAssociatedTypeBindings(
                callerAssociatedTypeBindings,
                layout: layout,
                typeDescription: typeDescription
            )
        }
        try associatedTypeBindings.validateReferenceBindings()
        if associatedTypeRequirements.isEmpty == false,
            associatedTypeBindings.isEmpty
        {
            let protocolName =
                associatedTypeRequirements.first?
                .protocolDescriptor.name ?? typeDescription
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "Associated types must be concretely bound. Use an existential such as `any \(protocolName)<ConcreteType>`, or supply `associatedTypes` when constructing a Stub."
            )
        }
        let requirementIDs = associatedTypeRequirements.map(\.id)
        let bindingIDs = associatedTypeBindings.ids
        guard requirementIDs.count == associatedTypeBindings.count,
            Set(requirementIDs).count == requirementIDs.count,
            associatedTypeBindings.hasUniqueIDs,
            Set(requirementIDs) == Set(bindingIDs)
        else {
            throw StubError.unsupportedProtocolShape(
                protocolName: typeDescription,
                reason: "Every associated-type declaration in the complete protocol layout must have exactly one concrete metadata binding with the same declaring protocol and name."
            )
        }
        return StubProtocolShape(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            representation: representation
        )
    }

    static func prepare(
        callerAssociatedTypeBindings: [AssociatedTypeBinding],
        requirements: [Requirement]
    ) throws -> PreparedStub {
        let context = PreparationContext(
            shape: try extractProtocolShape(
                callerAssociatedTypeBindings: callerAssociatedTypeBindings
            )
        )
        let methods: [MethodDescriptor]
        if requirements.isEmpty {
            methods = try context.discoverMethods(using: .automatic)
        } else {
            methods = try flatExplicitMethods(requirements, context: context)
        }

        try validateCallerBoundAssociatedTypeUse(methods, layout: context.layout)
        return try context.finalize(methods: methods)
    }

    static func resolveCallerAssociatedTypeBindings(
        _ suppliedBindings: [AssociatedTypeBinding],
        layout: ProtocolLayout,
        typeDescription: String
    ) throws -> AssociatedTypeBindings {
        let requirementIDs = Set(layout.associatedTypeRequirements.map(\.id))
        var suppliedIDs: Set<AssociatedTypeID> = []
        var bindings: [StubProtocolMetadata.AssociatedTypeBinding] = []
        for supplied in suppliedBindings {
            guard let descriptor = singleProtocolDescriptor(of: supplied.protocolType) else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: String(reflecting: supplied.protocolType),
                    reason: "An associated-type binding must name exactly one unbound declaring protocol."
                )
            }
            let identifier = AssociatedTypeID(
                protocolDescriptor: descriptor,
                name: supplied.name
            )
            guard layout.node(for: descriptor) != nil else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "The associated-type binding is declared by a protocol outside '\(typeDescription)'."
                )
            }
            guard requirementIDs.contains(identifier) else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "No associated type named '\(supplied.name)' is declared by this protocol."
                )
            }
            guard suppliedIDs.insert(identifier).inserted else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Associated type '\(supplied.name)' was bound more than once."
                )
            }
            bindings.append(
                StubProtocolMetadata.AssociatedTypeBinding(
                    protocolDescriptor: descriptor,
                    name: supplied.name,
                    type: supplied.type
                ))
        }
        return AssociatedTypeBindings(
            bindings,
            referenceAssociatedTypeIDs: Set(
                layout.associatedTypeRequirements
                    .filter(\.usesReferenceABI)
                    .map(\.id)
            )
        )
    }

    private static func validateCallerBoundAssociatedTypeUse(
        _ methods: [MethodDescriptor],
        layout: ProtocolLayout
    ) throws {
        for method in methods {
            guard
                let dependency = method.arguments.lazy.map(\.value.dependency)
                    .first(where: {
                        $0.isAssociatedTypeDependent
                            && ($0.containsReferenceAssociatedType == false
                                || $0.usesSupportedReferenceAssociatedTransport
                                    == false)
                    })
            else { continue }
            let protocolName = layout.callableRequirements[method.index]
                .protocolDescriptor.name
            let reason =
                dependency.containsReferenceAssociatedType
                ? "Requirement \(method.index) uses a caller-bound AnyObject-constrained associated type in an unsupported argument shape. Only direct values and one Optional layer have a proven dependent reference ABI."
                : "Requirement \(method.index) uses a caller-bound associated type in an argument. This initializer currently supports opaque associated types only in covariant result positions."
            throw StubError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
    }
}

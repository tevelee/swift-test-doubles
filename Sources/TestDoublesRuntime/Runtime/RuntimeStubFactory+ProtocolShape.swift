import InternalRuntimeContract
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport

#if canImport(ObjectiveC)
    import Foundation
#endif

/// Runtime-owned protocol-shape preparation behind the stub-factory facade.
///
/// The public target supplies only source-level metatypes and associated-type
/// binding requests. Existential inspection, descriptor identity, and ABI
/// validation stay in this target and fail with `RuntimeConstructionError`.
extension RuntimeStubFactory {
    package struct ProtocolShape {
        package let layout: ProtocolLayout
        package let associatedTypeBindings: AssociatedTypeBindings
        package let representation: StubExistentialRepresentation
    }

    package static func prepareProtocolShape(
        _ request: RuntimeProtocolShapeRequest
    ) throws -> ProtocolShape {
        let metadata = try inspectStubProtocolMetadata(
            request.protocolType,
            typeDescription: request.typeDescription
        )
        guard metadata.hasProtocolWithoutSwiftWitnessTable == false else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: request.typeDescription,
                reason: "The existential includes a protocol without a Swift witness table. Objective-C-only protocols use selector/IMP dispatch, which requires a separate runtime backend."
            )
        }
        guard metadata.protocols.isEmpty == false else {
            throw RuntimeConstructionError.typeIsNotProtocol(
                typeDescription: request.typeDescription
            )
        }
        let roots = metadata.protocols
        guard metadata.specialProtocol == .none else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: request.typeDescription,
                reason: "Special runtime protocols require dedicated representation and dispatch support."
            )
        }
        guard metadata.numberOfWitnessTables == roots.count else {
            let reason =
                metadata.numberOfWitnessTables < roots.count
                ? "The existential includes a protocol without a Swift witness table. Objective-C-only protocols use selector/IMP dispatch, which requires a separate runtime backend."
                : "The existential exposes more witness tables than protocol descriptors."
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: request.typeDescription,
                reason: reason
            )
        }

        let representation: StubExistentialRepresentation
        if metadata.hasSuperclassConstraint {
            guard let superclass = metadata.superclass else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: request.typeDescription,
                    reason: "The superclass-constrained existential metadata does not contain a superclass type."
                )
            }
            #if canImport(ObjectiveC)
                guard superclass is NSObject.Type else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: request.typeDescription,
                        reason: "Superclass-constrained runtime test doubles require an NSObject-backed superclass so a genuine instance can own the fabricated runtime resources."
                    )
                }
                representation = .superclassConstrained(superclass)
            #else
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: request.typeDescription,
                    reason: "Superclass-constrained runtime test doubles require the Objective-C runtime and an NSObject-backed superclass."
                )
            #endif
        } else {
            representation =
                metadata.isClassConstrained

                ? .classConstrained
                : .opaque
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
        if request.callerAssociatedTypeBindings.isEmpty {
            associatedTypeBindings = AssociatedTypeBindings(
                metadata.associatedTypeBindings,
                referenceAssociatedTypeIDs: referenceAssociatedTypeIDs
            )
        } else {
            guard metadata.associatedTypeBindings.isEmpty else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: request.typeDescription,
                    reason: "Caller-supplied associated-type bindings require an unbound protocol existential. Remove the bindings or construct the stub with an unbound `any Protocol` type."
                )
            }
            associatedTypeBindings = try resolveCallerAssociatedTypeBindings(
                request.callerAssociatedTypeBindings,
                layout: layout,
                typeDescription: request.typeDescription,
                referenceAssociatedTypeIDs: referenceAssociatedTypeIDs
            )
        }

        try associatedTypeBindings.validateReferenceBindings()
        if associatedTypeRequirements.isEmpty == false,
            associatedTypeBindings.isEmpty
        {
            let protocolName =
                associatedTypeRequirements.first?
                .protocolDescriptor.name ?? request.typeDescription
            throw RuntimeConstructionError.unsupportedProtocolShape(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: request.typeDescription,
                reason: "Every associated-type declaration in the complete protocol layout must have exactly one concrete metadata binding with the same declaring protocol and name."
            )
        }

        return ProtocolShape(
            layout: layout,
            associatedTypeBindings: associatedTypeBindings,
            representation: representation
        )
    }

    package static func validateCallerBoundAssociatedTypeUse(
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
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
    }

    package static func singleProtocolDescriptor(
        of type: Any.Type
    ) -> RuntimeProtocolDescriptor? {
        runtimeSingleProtocolDescriptor(of: type)
    }

    private static func resolveCallerAssociatedTypeBindings(
        _ suppliedBindings: [RuntimeAssociatedTypeBindingRequest],
        layout: ProtocolLayout,
        typeDescription: String,
        referenceAssociatedTypeIDs: Set<AssociatedTypeID>
    ) throws -> AssociatedTypeBindings {
        let requirementIDs = Set(layout.associatedTypeRequirements.map(\.id))
        var suppliedIDs: Set<AssociatedTypeID> = []
        var bindings: [StubProtocolMetadata.AssociatedTypeBinding] = []
        for supplied in suppliedBindings {
            guard let descriptor = runtimeSingleProtocolDescriptor(of: supplied.declaringProtocol)
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: String(reflecting: supplied.declaringProtocol),
                    reason: "An associated-type binding must name exactly one unbound declaring protocol."
                )
            }
            let identifier = AssociatedTypeID(
                protocolDescriptor: descriptor,
                name: supplied.name
            )
            guard layout.node(for: descriptor) != nil else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "The associated-type binding is declared by a protocol outside '\(typeDescription)'."
                )
            }
            guard requirementIDs.contains(identifier) else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "No associated type named '\(supplied.name)' is declared by this protocol."
                )
            }
            guard suppliedIDs.insert(identifier).inserted else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Associated type '\(supplied.name)' was bound more than once."
                )
            }
            bindings.append(
                StubProtocolMetadata.AssociatedTypeBinding(
                    protocolDescriptor: descriptor,
                    name: supplied.name,
                    type: supplied.type
                )
            )
        }
        return AssociatedTypeBindings(
            bindings,
            referenceAssociatedTypeIDs: referenceAssociatedTypeIDs
        )
    }
}

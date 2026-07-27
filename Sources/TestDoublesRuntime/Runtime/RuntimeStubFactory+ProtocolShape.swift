import Echo
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
            // A C++ foreign reference superclass constraint (e.g.
            // `Stub<any Widget & P>()`) is a real, distinct shape from an
            // NSObject superclass constraint, not a variant of "not
            // NSObject" -- give it its own diagnostic naming the actual
            // blocker (construction and resource-lifetime attachment, not
            // ownership rules) rather than suggesting NSObject as the fix.
            if reflect(superclass).kind == .foreignReferenceType {
                let superclassName = runtimeTypeName(superclass)
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: request.typeDescription,
                    reason: "Requires a genuine instance of the C++ foreign reference superclass '\(superclassName)', "
                        + "but automatic Stub construction has no generic way to default-construct one or to attach "
                        + "the fabricated runtime resources' lifetime to an arbitrary foreign-reference instance. "
                        + "Neither is implemented yet."
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

    /// Validates the raw method descriptors before they are materialized into
    /// a fabricated witness table. This deliberately stays below the public
    /// facade: every decision here depends on witness conventions, ABI
    /// layouts, or runtime transport support rather than recorder semantics.
    package static func validate(
        methods: [MethodDescriptor],
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation
    ) throws -> [Int: RuntimeModifyDispatch] {
        for method in methods {
            let protocolName = layout.callableRequirements[method.index]
                .protocolDescriptor.name
            let selfArguments = method.arguments.filter {
                switch $0.value.convention {
                    case .selfType, .optionalSelf: true
                    case .concrete, .associatedType, .methodGenericParameter: false
                }
            }
            let allowsAutomaticSelfArguments =
                selfArguments.isEmpty == false
                && method.origin == .automatic
                && method.kind == .method
                && method.receiver == .instance
                && {
                    if case .superclassConstrained = representation {
                        return false
                    }
                    return true
                }()
            if case .superclassConstrained = representation,
                method.returnConvention == .selfType
                    || method.returnConvention == .optionalSelf
                    || method.kind == .initializer
            {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) returns dynamic Self from a superclass-constrained existential. This requires separate subclass metadata and initializer runtime support."
                )
            }
            if method.kind == .initializer,
                method.arguments.contains(where: { $0.ownership == .borrowed })
            {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) has borrowed storage where its witness convention requires owned arguments."
                )
            }
            if selfArguments.isEmpty == false {
                if case .superclassConstrained = representation {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) contains a Self argument in a superclass-constrained existential. This requires subclass-specific argument metadata and remains unsupported."
                    )
                }
                guard method.origin == .automatic else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason:
                            "Requirement \(method.index) contains a Self argument described by an explicit schema. "
                            + "Direct and Optional Self arguments require automatic witness discovery so their semantic identity cannot be erased by function conversion."
                    )
                }
                guard method.kind == .method,
                    method.receiver == .instance
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) contains a Self argument outside an automatic instance method. Initializers, accessors, and static Self arguments remain unsupported."
                    )
                }
            }
            for argument in method.arguments where argument.ownership == .owned {
                switch method.kind {
                    case .setter, .initializer:
                        break
                    case .method:
                        let isSelfArgument =
                            argument.value.convention == .selfType
                            || argument.value.convention == .optionalSelf
                        guard
                            (isSelfArgument && allowsAutomaticSelfArguments)
                                || argument.value.dependency.isAssociatedTypeDependent
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: protocolName,
                                reason: "Requirement \(method.index) consumes a non-dependent method argument. Consuming method support accepts values that depend on an associated type."
                            )
                        }
                    case .getter:
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Requirement \(method.index) has an owned getter argument."
                        )
                }
            }
            if method.typedErrorType != nil,
                method.returnConvention == .selfType
                    || method.returnConvention == .optionalSelf
            {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) combines typed throws with an unsupported Self result convention."
                )
            }
            switch method.kind {
                case .initializer:
                    guard method.receiver == .metatype,
                        method.returnConvention == .selfType || method.returnConvention == .optionalSelf
                    else {
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Requirement \(method.index) is not a supported Self-returning initializer."
                        )
                    }
                case .method, .getter, .setter:
                    break
            }
            let concreteTypes = method.arguments.map(\.value.type) + [method.returnType]
            let dependentValues = method.arguments.map(\.value) + [method.result]
            if dependentValues.contains(where: {
                if $0.dependency.isAssociatedTypeDependent {
                    return runtimeIsFunctionType($0.type)
                }
                return false
            }) {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) uses a function value through an associated type. Dependent function-value transport is unsupported; use a hand-written test double."
                )
            }
            let containsFunction = concreteTypes.contains {
                runtimeIsFunctionType($0)
            }
            if containsFunction {
                guard method.origin == .automatic || method.typedWitnessAdapterFactory != nil else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) contains a function argument or result. Supply an explicit Requirement with a compiler-typed `using:` adapter."
                    )
                }
                if method.origin == .automatic {
                    let argumentReason = method.arguments.lazy.compactMap { argument in
                        FunctionReabstraction.automaticArgumentUnsupportedReason(
                            for: argument.value.type
                        )
                    }.first
                    let resultReason =
                        FunctionReabstraction
                        .automaticResultUnsupportedReason(for: method.returnType)
                    if let unsupported = argumentReason ?? resultReason {
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Requirement \(method.index) contains an unsupported automatic function value. \(unsupported)"
                        )
                    }
                }
                if let factory = method.typedWitnessAdapterFactory,
                    let incompatibility = factory.incompatibility(with: method)
                {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) has an incompatible typed adapter. \(incompatibility)"
                    )
                }
            } else if method.typedWitnessAdapterFactory != nil {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) supplies a typed adapter but has no direct function argument or result."
                )
            }
            if let reason = runtimeSIMDUnsupportedReason(for: method) {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) contains an unsupported SIMD value. \(reason)"
                )
            }
            if let reason = runtimeMethodGenericParameterUnsupportedReason(for: method) {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) has a requirement-level generic parameter. \(reason)"
                )
            }
            if method.kind == .setter {
                guard method.arguments.first?.ownership == .owned,
                    method.arguments.dropFirst().allSatisfy({ $0.ownership == .borrowed }),
                    method.returnType == Void.self,
                    method.isThrowing == false,
                    method.isAsync == false
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) is not a synchronous setter with one owned value followed by borrowed indices."
                    )
                }
            }
            if method.typedWitnessAdapterFactory == nil,
                let reason = unsupportedRuntimeReason(for: method, architecture: .current)
            {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) is not supported. \(reason)"
                )
            }
        }

        return try validateModifyCoroutinePairs(methods: methods, layout: layout)
    }

    package static func singleProtocolDescriptor(
        of type: Any.Type
    ) -> RuntimeProtocolDescriptor? {
        runtimeSingleProtocolDescriptor(of: type)
    }

    private static func validateModifyCoroutinePairs(
        methods: [MethodDescriptor],
        layout: ProtocolLayout
    ) throws -> [Int: RuntimeModifyDispatch] {
        let methodsByIndex = Dictionary(
            uniqueKeysWithValues: methods.map { ($0.index, $0) }
        )
        var descriptors: [Int: RuntimeModifyDispatch] = [:]
        for node in layout.nodes {
            for modify in node.modifyCoroutineRequirements {
                guard let getter = methodsByIndex[modify.getterDispatchIndex],
                    let setter = methodsByIndex[modify.setterDispatchIndex],
                    modify.setterDispatchIndex
                        == modify.getterDispatchIndex + 1,
                    getter.receiver == modify.receiver,
                    setter.receiver == modify.receiver,
                    modifyPairIsCompatible(getter: getter, setter: setter)
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: node.runtimeProtocolDescriptor.name,
                        reason: "The _modify requirement at witness index \(modify.witnessIndex) does not have a compatible synchronous getter/setter pair."
                    )
                }
                descriptors[modify.getterDispatchIndex] =
                    RuntimeModifyDispatch(
                        getterSlot: modify.getterDispatchIndex,
                        setterSlot: modify.setterDispatchIndex
                    )
            }
        }
        return descriptors
    }

    private static func modifyPairIsCompatible(
        getter: MethodDescriptor,
        setter: MethodDescriptor
    ) -> Bool {
        guard let newValue = setter.arguments.first else { return false }
        let indices = setter.arguments.dropFirst()
        return getter.kind == .getter
            && setter.kind == .setter
            && getter.receiver == setter.receiver
            && getter.isAsync == false
            && getter.isThrowing == false
            && setter.isAsync == false
            && setter.isThrowing == false
            && newValue.ownership == .owned
            && getter.result.matches(newValue.value)
            && getter.arguments.count == indices.count
            && zip(getter.arguments, indices).allSatisfy {
                $0.ownership == .borrowed && $0.matches($1)
            }
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

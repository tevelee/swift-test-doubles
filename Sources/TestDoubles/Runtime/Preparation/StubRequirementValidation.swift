import InternalRuntimeContract
import TestDoublesRuntime
import TestDoublesRuntimeMetadata

extension Stub {
    static func validate(
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
                    case .concrete, .associatedType: false
                }
            }
            let allowsAutomaticSelfArguments =
                selfArguments.isEmpty == false
                && method.origin == .automatic
                && method.kind == .method
                && method.receiver == .instance
                && method.isThrowing == false
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
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) returns dynamic Self from a superclass-constrained existential. This requires separate subclass metadata and initializer runtime support."
                )
            }
            if method.kind == .initializer,
                method.arguments.contains(where: { $0.ownership == .borrowed })
            {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) has borrowed storage where its witness convention requires owned arguments."
                )
            }
            if selfArguments.isEmpty == false {
                if case .superclassConstrained = representation {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) contains a Self argument in a superclass-constrained existential. This requires subclass-specific argument metadata and remains unsupported."
                    )
                }
                guard method.origin == .automatic else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason:
                            "Requirement \(method.index) contains a Self argument described by an explicit schema. "
                            + "Direct and Optional Self arguments require automatic witness discovery so their semantic identity cannot be erased by function conversion."
                    )
                }
                guard method.kind == .method,
                    method.receiver == .instance
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) contains a Self argument outside an automatic instance method. Initializers, accessors, and static Self arguments remain unsupported."
                    )
                }
                guard method.isThrowing == false else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) combines a Self argument with throwing effects. This bounded slice supports only nonthrowing synchronous or async methods."
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
                            throw StubError.unsupportedProtocolShape(
                                protocolName: protocolName,
                                reason: "Requirement \(method.index) consumes a non-dependent method argument. Consuming method support accepts values that depend on an associated type."
                            )
                        }
                    case .getter:
                        throw StubError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Requirement \(method.index) has an owned getter argument."
                        )
                }
            }
            if method.typedErrorType != nil,
                method.returnConvention == .selfType
                    || method.returnConvention == .optionalSelf
            {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) combines typed throws with an unsupported Self result convention."
                )
            }
            switch method.kind {
                case .initializer:
                    guard method.receiver == .metatype,
                        method.returnConvention == .selfType || method.returnConvention == .optionalSelf
                    else {
                        throw StubError.unsupportedProtocolShape(
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
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) uses a function value through an associated type. Dependent function-value transport is unsupported; use a hand-written test double."
                )
            }
            let containsFunction = concreteTypes.contains {
                runtimeIsFunctionType($0)
            }
            if containsFunction {
                guard method.origin == .automatic || method.typedWitnessAdapterFactory != nil else {
                    throw StubError.unsupportedProtocolShape(
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
                        throw StubError.unsupportedProtocolShape(
                            protocolName: protocolName,
                            reason: "Requirement \(method.index) contains an unsupported automatic function value. \(unsupported)"
                        )
                    }
                }
                if let factory = method.typedWitnessAdapterFactory,
                    let incompatibility = factory.incompatibility(with: method)
                {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) has an incompatible typed adapter. \(incompatibility)"
                    )
                }
            } else if method.typedWitnessAdapterFactory != nil {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) supplies a typed adapter but has no direct function argument or result."
                )
            }
            if let reason = runtimeSIMDUnsupportedReason(for: method) {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) contains an unsupported SIMD value. \(reason)"
                )
            }
            if method.kind == .setter {
                guard method.arguments.first?.ownership == .owned,
                    method.arguments.dropFirst().allSatisfy({ $0.ownership == .borrowed }),
                    method.returnType == Void.self,
                    method.isThrowing == false,
                    method.isAsync == false
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason: "Requirement \(method.index) is not a synchronous setter with one owned value followed by borrowed indices."
                    )
                }
            }
            if method.typedWitnessAdapterFactory == nil,
                let reason = unsupportedRuntimeReason(for: method, architecture: .current)
            {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) is not supported. \(reason)"
                )
            }
        }

        return try validateModifyCoroutinePairs(methods: methods, layout: layout)
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
                    throw StubError.unsupportedProtocolShape(
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

}

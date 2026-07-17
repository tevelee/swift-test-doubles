import Echo

extension Stub {
    static func validate(
        methods: [MethodDescriptor],
        layout: ProtocolLayout,
        representation: StubExistentialRepresentation
    ) throws -> [Int: ModifyDispatchDescriptor] {
        for method in methods {
            let protocolName = layout.callableRequirements[method.index]
                .protocolDescriptor.name
            let selfArguments = method.arguments.contains {
                switch $0.value.convention {
                    case .selfType, .optionalSelf: true
                    case .concrete, .associatedType: false
                }
            }
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
            for argument in method.arguments where argument.ownership == .owned {
                switch method.kind {
                    case .setter, .initializer:
                        break
                    case .method:
                        guard case .associatedType = argument.value.dependency else {
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
            if selfArguments {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) contains a direct Self argument. Dynamic Self support accepts Self only in result position."
                )
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
            let containsFunction = concreteTypes.contains {
                reflect($0).kind == .function
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
            if concreteTypes.contains(where: containsSIMDStorage) {
                throw StubError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "Requirement \(method.index) contains a SIMD value. SIMD register transport is unsupported; use a small hand-written test double."
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
    ) throws -> [Int: ModifyDispatchDescriptor] {
        let methodsByIndex = Dictionary(
            uniqueKeysWithValues: methods.map { ($0.index, $0) }
        )
        var descriptors: [Int: ModifyDispatchDescriptor] = [:]
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
                        protocolName: node.descriptor.name,
                        reason: "The _modify requirement at witness index \(modify.witnessIndex) does not have a compatible synchronous getter/setter pair."
                    )
                }
                descriptors[modify.getterDispatchIndex] =
                    ModifyDispatchDescriptor(
                        getterDispatchIndex: modify.getterDispatchIndex,
                        setterDispatchIndex: modify.setterDispatchIndex
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

    static func validateAgainstLinkedConformances(
        _ supplied: [MethodDescriptor],
        layout: ProtocolLayout,
        associatedTypeBindings: AssociatedTypeBindings,
        selfIsClassConstrained: Bool
    ) throws {
        let requiresStrictDiscovery = associatedTypeBindings.isEmpty == false
        var witnessTables: [ProtocolLayout.DescriptorID: WitnessTable] = [:]
        for root in layout.roots {
            guard let conformance = Echo.findConformance(to: root) else { continue }
            var collected = witnessTables
            do {
                try collectLinkedWitnessTables(
                    descriptor: root,
                    witnessTable: conformance.witnessTablePattern,
                    layout: layout,
                    into: &collected
                )
                witnessTables = collected
            } catch {
                if requiresStrictDiscovery { throw error }
            }
        }

        let discoverableRequirements = layout.callableRequirements.filter {
            witnessTables[ProtocolLayout.DescriptorID($0.protocolDescriptor)] != nil
                || resilientRequirementSymbolName($0) != nil
        }
        for requirement in discoverableRequirements {
            let expected: MethodDescriptor
            do {
                guard
                    let discovered = try discoverMethods(
                        witnessTables: witnessTables,
                        layout: layout,
                        requirements: [requirement],
                        associatedTypeBindings: associatedTypeBindings,
                        selfIsClassConstrained: selfIsClassConstrained,
                        getterEffectPolicy: .explicitRequirementValidation
                    ).first
                else {
                    continue
                }
                expected = discovered
            } catch let error as StubError {
                // Once linked discovery identifies an unsupported ABI shape,
                // explicit metadata must not bypass that fail-closed boundary.
                if case .unsupportedProtocolShape = error { throw error }
                if requiresStrictDiscovery { throw error }
                continue
            } catch {
                if requiresStrictDiscovery { throw error }
                continue
            }
            guard supplied.indices.contains(expected.index) else { continue }
            let actual = supplied[expected.index]
            guard actual.hasSameSignature(as: expected) == false else { continue }
            let protocolName = layout.callableRequirements[expected.index]
                .protocolDescriptor.name
            throw StubError.requirementMismatch(
                protocolName: protocolName,
                requirementIndex: expected.index,
                expected: expected.signatureDescription,
                actual: actual.signatureDescription
            )
        }
    }

}

/// Whether a value of `type` stores SIMD vector data anywhere the register
/// codecs would transport directly. The trampoline does not model vector
/// registers, so these types are rejected at construction rather than
/// exchanged incorrectly at invocation.
private func containsSIMDStorage(_ type: Any.Type) -> Bool {
    var visited: Set<UInt> = []
    return containsSIMDStorage(type, visited: &visited)
}

private func containsSIMDStorage(_ type: Any.Type, visited: inout Set<UInt>) -> Bool {
    if type is any SIMD.Type {
        return true
    }
    let metadata = reflect(type)
    if let tupleMetadata = metadata as? TupleMetadata {
        return tupleMetadata.safelyInitializedElements.contains {
            containsSIMDStorage($0.type, visited: &visited)
        }
    }
    guard let structMetadata = reflectStruct(type) else {
        return false
    }
    let key = UInt(bitPattern: structMetadata.ptr)
    guard visited.insert(key).inserted else {
        return false
    }
    defer { visited.remove(key) }
    return structMetadata.descriptor.fields.records.contains { field in
        guard field.hasMangledTypeName,
            let fieldType = structMetadata.type(of: field.mangledTypeName)
        else {
            return false
        }
        return containsSIMDStorage(fieldType, visited: &visited)
    }
}

func runtimeConformance(
    _ type: UnsafeRawPointer,
    _ protocolDescriptor: UnsafeRawPointer
) -> UnsafeRawPointer? {
    typealias Function =
        @convention(c) (
            UnsafeRawPointer,
            UnsafeRawPointer
        ) -> UnsafeRawPointer?
    guard let function: Function = RuntimeSymbols.function(named: "swift_conformsToProtocol")
    else { return nil }
    return function(type, protocolDescriptor)
}

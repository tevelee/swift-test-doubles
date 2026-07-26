import Echo

extension ProtocolLayout {
    struct Builder {
        typealias LocalModifyRequirement = (
            witnessIndex: Int,
            getterWitnessIndex: Int,
            setterWitnessIndex: Int,
            receiver: StubRequirementReceiver,
            abi: ModifyCoroutineABI
        )
        typealias LocalReadRequirement = (
            witnessIndex: Int,
            recorderWitnessIndex: Int,
            receiver: StubRequirementReceiver,
            abi: ReadCoroutineABI
        )
        typealias LocalCallableRequirement = (
            witnessIndex: Int,
            kind: StubRequirementKind,
            receiver: StubRequirementReceiver
        )
        typealias LocalAssociatedType = (
            witnessIndex: Int,
            name: String,
            usesReferenceABI: Bool
        )

        let contextName: String
        let allowsClassConstraint: Bool
        var visited: Set<DescriptorID> = []
        var active: Set<DescriptorID> = []
        var nodes: [Node] = []
        var callableRequirements: [CallableRequirement] = []

        mutating func visit(_ descriptor: ProtocolDescriptor) throws {
            let identifier = DescriptorID(descriptor)
            guard visited.contains(identifier) == false else { return }
            guard active.insert(identifier).inserted else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: contextName,
                    reason: "Protocol inheritance contains a cycle through '\(descriptor.name)'."
                )
            }
            defer { active.remove(identifier) }

            let local = try validatedLocalLayout(for: descriptor)
            for baseProtocol in local.baseProtocols {
                try visit(baseProtocol.descriptor)
            }

            let requirements = local.callableRequirements.map { localRequirement in
                let requirement = CallableRequirement(
                    protocolDescriptor: descriptor,
                    witnessIndex: localRequirement.witnessIndex,
                    dispatchIndex: callableRequirements.count,
                    kind: localRequirement.kind,
                    receiver: localRequirement.receiver
                )
                callableRequirements.append(requirement)
                return requirement
            }
            nodes.append(
                Node(
                    descriptor: descriptor,
                    baseProtocols: local.baseProtocols,
                    associatedTypes: local.associatedTypes.map {
                        AssociatedTypeRequirement(
                            protocolDescriptor: descriptor,
                            witnessIndex: $0.witnessIndex,
                            name: $0.name,
                            usesReferenceABI: $0.usesReferenceABI
                        )
                    },
                    associatedConformances: local.associatedConformances.map {
                        AssociatedConformanceRequirement(
                            protocolDescriptor: descriptor,
                            witnessIndex: $0.witnessIndex,
                            associatedTypeName: $0.associatedTypeName,
                            constraint: $0.constraint
                        )
                    },
                    callableRequirements: requirements,
                    readCoroutineRequirements: try local.readCoroutineRequirements.map {
                        readRequirement in
                        guard
                            let dispatch = requirements.first(where: {
                                $0.witnessIndex == readRequirement.recorderWitnessIndex
                            })
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "A read coroutine is missing its getter dispatch mapping."
                            )
                        }
                        return ReadCoroutineRequirement(
                            witnessIndex: readRequirement.witnessIndex,
                            recorderDispatchIndex: dispatch.dispatchIndex,
                            receiver: readRequirement.receiver,
                            abi: readRequirement.abi
                        )
                    },
                    modifyCoroutineRequirements: try local.modifyCoroutineRequirements.map {
                        modifyRequirement in
                        guard
                            let getter = requirements.first(where: {
                                $0.witnessIndex == modifyRequirement.getterWitnessIndex
                            }),
                            let setter = requirements.first(where: {
                                $0.witnessIndex == modifyRequirement.setterWitnessIndex
                            })
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "A _modify coroutine is missing its getter or setter dispatch mapping."
                            )
                        }
                        return ModifyCoroutineRequirement(
                            witnessIndex: modifyRequirement.witnessIndex,
                            getterDispatchIndex: getter.dispatchIndex,
                            setterDispatchIndex: setter.dispatchIndex,
                            receiver: modifyRequirement.receiver,
                            abi: modifyRequirement.abi
                        )
                    }
                ))
            visited.insert(identifier)
        }

        private func validatedLocalLayout(
            for descriptor: ProtocolDescriptor
        ) throws -> (
            baseProtocols: [BaseProtocol],
            associatedTypes: [LocalAssociatedType],
            associatedConformances: [(
                witnessIndex: Int,
                associatedTypeName: String,
                constraint: ProtocolDescriptor
            )],
            callableRequirements: [LocalCallableRequirement],
            readCoroutineRequirements: [LocalReadRequirement],
            modifyCoroutineRequirements: [LocalModifyRequirement]
        ) {
            // Echo constructs these arrays with
            // `unsafeUninitializedCapacity`. Its zero-capacity path mutates
            // Swift's shared empty-array storage, which ThreadSanitizer reports
            // when independent stubs are constructed in parallel. Bypass that
            // path for empty metadata and cache non-empty arrays once.
            let localRequirements: [ProtocolRequirement] =
                descriptor.numRequirements == 0 ? [] : descriptor.requirements
            let localRequirementKinds = try validatedRequirementKinds(
                localRequirements,
                for: descriptor
            )
            let baseWitnessIndices = localRequirementKinds.enumerated().compactMap {
                index, kind in
                kind == .baseProtocol ? index : nil
            }
            let signature: [GenericRequirementDescriptor] =
                descriptor.numRequirementsInSignature == 0
                ? []
                : descriptor.requirementSignature
            let associatedTypeNames = descriptor.associatedTypeNames
                .split(separator: " ")
                .map(String.init)
            let (conformanceSignature, classLayoutRequirements) =
                try validatedSignatureConstraints(signature, for: descriptor)
            let referenceAssociatedTypeNames =
                try validateClassLayoutRequirements(
                    classLayoutRequirements,
                    for: descriptor,
                    associatedTypeNames: associatedTypeNames
                )
            let associatedTypeWitnessIndices = localRequirementKinds.enumerated().compactMap {
                index, kind in
                kind == .associatedTypeAccessFunction ? index : nil
            }
            let associatedConformanceWitnessIndices = localRequirementKinds.enumerated().compactMap {
                index, kind in
                kind == .associatedConformanceAccessFunction ? index : nil
            }
            guard associatedTypeNames.count == associatedTypeWitnessIndices.count else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Associated-type names do not match their witness-table entries."
                )
            }

            // A descriptor that directly declares an associated type alongside
            // inherited protocols carries both kinds of constraint in the same
            // requirement signature. Self is always the protocol's depth-0
            // index-0 generic parameter, mangled as the single byte "x"; any
            // other entry is a dependent member of Self (the associated type),
            // so the two constraint kinds are told apart by that byte rather
            // than assumed mutually exclusive.
            let selfConformances = conformanceSignature.filter(constrainsProtocolSelf)
            let dependentConformances = conformanceSignature.filter {
                constrainsProtocolSelf($0) == false
            }
            guard selfConformances.count == baseWitnessIndices.count else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Inherited-protocol metadata is malformed or uses an unsupported constraint."
                )
            }
            let baseProtocols = zip(
                selfConformances.map(\.protocol),
                baseWitnessIndices
            ).map {
                BaseProtocol(descriptor: $0.0, witnessIndex: $0.1)
            }

            let associatedConformances:
                [(
                    witnessIndex: Int,
                    associatedTypeName: String,
                    constraint: ProtocolDescriptor
                )]
            if associatedTypeNames.isEmpty {
                guard dependentConformances.isEmpty,
                    associatedConformanceWitnessIndices.isEmpty
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: descriptor.name,
                        reason: "Inherited-protocol metadata is malformed or uses an unsupported constraint."
                    )
                }
                associatedConformances = []
            } else {
                guard dependentConformances.count == associatedConformanceWitnessIndices.count else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: descriptor.name,
                        reason: "Associated-type conformance constraints do not match their witness-table entries."
                    )
                }
                associatedConformances = try zip(
                    associatedConformanceWitnessIndices,
                    dependentConformances
                ).map { witnessIndex, conformance in
                    guard
                        let identity = parseProtocolAssociatedTypeReference(
                            at: conformance.paramMangledName
                        ),
                        DescriptorID(identity.protocolDescriptor) == DescriptorID(descriptor),
                        associatedTypeNames.contains(identity.name)
                    else {
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "An associated-type conformance constraint does not identify a declared associated type."
                        )
                    }
                    return (
                        witnessIndex: witnessIndex,
                        associatedTypeName: identity.name,
                        constraint: conformance.protocol
                    )
                }
            }
            let associatedTypes: [LocalAssociatedType] = zip(
                associatedTypeWitnessIndices,
                associatedTypeNames
            ).map { ($0.0, $0.1, referenceAssociatedTypeNames.contains($0.1)) }

            var callableRequirements: [LocalCallableRequirement] = []
            var readCoroutineRequirements: [LocalReadRequirement] = []
            var modifyCoroutineRequirements: [LocalModifyRequirement] = []
            for (index, requirement) in localRequirements.enumerated() {
                let requirementKind = localRequirementKinds[index]
                switch requirementKind {
                    case .baseProtocol:
                        guard requirement.flags.isInstance == false else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Inherited-protocol requirement \(index) has invalid flags."
                            )
                        }

                    case .method, .getter:
                        guard let kind = StubRequirementKind(requirementKind) else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Requirement \(index) has invalid callable flags."
                            )
                        }
                        callableRequirements.append(
                            (
                                index,
                                kind,
                                requirement.flags.isInstance ? .instance : .metatype
                            ))

                    case .`init`:
                        guard requirement.flags.isInstance == false,
                            let kind = StubRequirementKind(requirementKind)
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Initializer requirement \(index) has invalid instance flags."
                            )
                        }
                        callableRequirements.append((index, kind, .metatype))

                    case .associatedTypeAccessFunction,
                        .associatedConformanceAccessFunction:
                        guard requirement.flags.isInstance == false else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Associated requirement \(index) has invalid instance flags."
                            )
                        }

                    case .setter:
                        guard index > localRequirements.startIndex,
                            index + 1 < localRequirements.endIndex,
                            localRequirementKinds[index - 1] == .getter,
                            localRequirements[index - 1].flags.isInstance == requirement.flags.isInstance,
                            localRequirementKinds[index + 1] == .modifyCoroutine,
                            localRequirements[index + 1].flags.isInstance == requirement.flags.isInstance,
                            let kind = StubRequirementKind(requirementKind)
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Requirement \(index) is a setter outside Swift's ordinary getter/setter/modify property layout."
                            )
                        }
                        callableRequirements.append(
                            (
                                index,
                                kind,
                                requirement.flags.isInstance ? .instance : .metatype
                            ))

                    case .modifyCoroutine:
                        guard index >= localRequirements.startIndex + 2,
                            localRequirementKinds[index - 1] == .setter,
                            localRequirements[index - 1].flags.isInstance == requirement.flags.isInstance,
                            localRequirementKinds[index - 2] == .getter,
                            localRequirements[index - 2].flags.isInstance == requirement.flags.isInstance
                        else {
                            throw RuntimeConstructionError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Requirement \(index) is an unsupported standalone _modify coroutine."
                            )
                        }
                        modifyCoroutineRequirements.append(
                            (
                                witnessIndex: index,
                                getterWitnessIndex: index - 2,
                                setterWitnessIndex: index - 1,
                                receiver: requirement.flags.isInstance ? .instance : .metatype,
                                abi:
                                    requirement.flags.isCalleeAllocatedCoroutine
                                    ? .yieldOnce2 : .yieldOnce
                            ))

                    case .readCoroutine:
                        try appendReadCoroutineRequirement(
                            at: index,
                            from: localRequirements,
                            kinds: localRequirementKinds,
                            for: descriptor,
                            callableRequirements: &callableRequirements,
                            readCoroutineRequirements: &readCoroutineRequirements
                        )

                    @unknown default:
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "Requirement \(index) is a \(requirementKind). Only inherited protocols, initializers, methods, ordinary getters, and direct property setters are supported."
                        )
                }
            }

            return (
                baseProtocols,
                associatedTypes,
                associatedConformances,
                callableRequirements,
                readCoroutineRequirements,
                modifyCoroutineRequirements
            )
        }

        private func validatedRequirementKinds(
            _ requirements: [ProtocolRequirement],
            for descriptor: ProtocolDescriptor
        ) throws -> [ProtocolRequirement.Kind] {
            try requirements.enumerated().map { index, requirement in
                guard let kind = protocolRequirementKind(requirement) else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: descriptor.name,
                        reason: "Requirement \(index) has an unknown ABI kind."
                    )
                }
                return kind
            }
        }

        private func validatedSignatureConstraints(
            _ signature: [GenericRequirementDescriptor],
            for descriptor: ProtocolDescriptor
        ) throws -> (
            conformances: [GenericRequirementDescriptor],
            classLayouts: [GenericRequirementDescriptor]
        ) {
            var conformances: [GenericRequirementDescriptor] = []
            var classLayouts: [GenericRequirementDescriptor] = []
            for requirement in signature {
                guard let kind = genericRequirementKind(requirement) else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: descriptor.name,
                        reason: "Only inherited-protocol, associated-type conformance, and class-layout constraints are supported."
                    )
                }
                switch kind {
                    case .protocol:
                        conformances.append(requirement)

                    case .layout:
                        classLayouts.append(requirement)

                    case .invertedProtocols:
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: invertedProtocolDiagnostic(for: requirement)
                        )

                    case .sameType, .baseClass, .sameConformance, .sameShape:
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "Only inherited-protocol, associated-type conformance, and class-layout constraints are supported."
                        )
                }
            }
            return (conformances, classLayouts)
        }

        private func appendReadCoroutineRequirement(
            at index: Int,
            from localRequirements: [ProtocolRequirement],
            kinds: [ProtocolRequirement.Kind],
            for descriptor: ProtocolDescriptor,
            callableRequirements: inout [LocalCallableRequirement],
            readCoroutineRequirements: inout [LocalReadRequirement]
        ) throws {
            let requirement = localRequirements[index]
            let receiver: StubRequirementReceiver =
                requirement.flags.isInstance ? .instance : .metatype
            let usesYieldOnce2 = requirement.flags.isCalleeAllocatedCoroutine
            if usesYieldOnce2,
                index > localRequirements.startIndex,
                kinds[index - 1] == .readCoroutine,
                localRequirements[index - 1].flags.isCalleeAllocatedCoroutine == false
            {
                // Swift 6.4's paired `yielding borrow` witness was already
                // recorded with its legacy `read` slot.
                return
            }

            if usesYieldOnce2 {
                // Swift 6.3 emits one physical `read2` witness.
                callableRequirements.append((index, .getter, receiver))
                readCoroutineRequirements.append(
                    (
                        witnessIndex: index,
                        recorderWitnessIndex: index,
                        receiver: receiver,
                        abi: .yieldOnce2
                    ))
                return
            }

            let pairedIndex = index + 1
            guard pairedIndex < localRequirements.endIndex,
                kinds[pairedIndex] == .readCoroutine,
                localRequirements[pairedIndex].flags.isCalleeAllocatedCoroutine,
                localRequirements[pairedIndex].flags.isInstance
                    == requirement.flags.isInstance
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "The legacy read witness at index \(index) is missing its adjacent Swift 6.4 yielding-borrow witness."
                )
            }

            // Swift 6.4 emits a legacy yield_once slot followed by a
            // yield_once_2 slot for one logical accessor. Expose only the
            // supported second slot to discovery and APIs, while retaining
            // both physical coordinates for witness-table fabrication.
            callableRequirements.append((pairedIndex, .getter, receiver))
            readCoroutineRequirements.append(
                (
                    witnessIndex: index,
                    recorderWitnessIndex: pairedIndex,
                    receiver: receiver,
                    abi: .yieldOnce
                ))
            readCoroutineRequirements.append(
                (
                    witnessIndex: pairedIndex,
                    recorderWitnessIndex: pairedIndex,
                    receiver: receiver,
                    abi: .yieldOnce2
                ))
        }

        private func validateClassLayoutRequirements(
            _ requirements: [GenericRequirementDescriptor],
            for descriptor: ProtocolDescriptor,
            associatedTypeNames: [String]
        ) throws -> Set<String> {
            guard
                requirements.allSatisfy({
                    guard genericRequirementLayoutKind($0) != nil else {
                        return false
                    }
                    return $0.layoutKind == .class
                })
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Only the AnyObject class layout constraint is supported."
                )
            }
            let selfRequirements = requirements.filter(constrainsProtocolSelf)
            guard selfRequirements.count <= 1,
                selfRequirements.isEmpty || allowsClassConstraint
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "A Self: AnyObject requirement requires class-constrained existential metadata."
                )
            }
            let constrainedAssociatedTypeNames =
                try requirements
                .filter { constrainsProtocolSelf($0) == false }
                .map { requirement in
                    guard
                        let identity = parseProtocolAssociatedTypeReference(
                            at: requirement.paramMangledName
                        ),
                        DescriptorID(identity.protocolDescriptor) == DescriptorID(descriptor),
                        associatedTypeNames.contains(identity.name)
                    else {
                        throw RuntimeConstructionError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "A class-layout constraint does not identify a declared associated type."
                        )
                    }
                    return identity.name
                }
            guard Set(constrainedAssociatedTypeNames).count == constrainedAssociatedTypeNames.count else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "An associated type has duplicate class-layout constraints."
                )
            }
            return Set(constrainedAssociatedTypeNames)
        }
    }
}

private func constrainsProtocolSelf(_ requirement: GenericRequirementDescriptor) -> Bool {
    let name = requirement.paramMangledName.assumingMemoryBound(to: UInt8.self)
    return name[0] == UInt8(ascii: "x") && name[1] == 0
}

private func protocolRequirementKind(
    _ requirement: ProtocolRequirement
) -> ProtocolRequirement.Kind? {
    // Echo's `flags.kind` force-unwraps this enum. Decode the stable flag
    // field first so requirements introduced by newer Swift runtimes fail
    // closed instead of trapping before this parser can reject them.
    ProtocolRequirement.Kind(
        rawValue: UInt8(truncatingIfNeeded: requirement.flags.bits & 0xF)
    )
}

private func genericRequirementKind(
    _ requirement: GenericRequirementDescriptor
) -> GenericRequirementKind? {
    // Echo's `flags.kind` force-unwraps this enum. Read the stable flags word
    // first so a newer requirement kind is rejected rather than trapping in
    // the library.
    GenericRequirementKind(
        rawValue: UInt8(truncatingIfNeeded: requirement.flags.bits & 0x1F)
    )
}

private func genericRequirementLayoutKind(
    _ requirement: GenericRequirementDescriptor
) -> GenericRequirementLayoutKind? {
    // The requirement payload follows the flags and relative parameter-name
    // pointer. Reading the raw stable ABI value avoids Echo force-unwrapping a
    // newer layout-kind enum before this parser can reject it.
    let pointer = unsafeBitCast(requirement, to: UnsafeRawPointer.self)
    return GenericRequirementLayoutKind(
        rawValue: pointer.load(fromByteOffset: 8, as: UInt32.self)
    )
}

private func invertedProtocolDiagnostic(
    for requirement: GenericRequirementDescriptor
) -> String {
    // `validatedSignatureConstraints` checks the raw kind before calling this
    // property, which preserves fail-closed parsing when future Swift runtimes
    // add generic requirement kinds.
    let protocols = requirement.invertedProtocols
    if protocols.hasUnknownProtocols {
        return "The protocol uses an unknown inverted-protocol constraint. Runtime test doubles require Copyable and Escapable payloads."
    }
    if protocols.invertsCopyable, protocols.invertsEscapable {
        return "The protocol relaxes Copyable and Escapable with `~Copyable` and `~Escapable`. Runtime test doubles record escaping `Any` values, which require copyable, escapable payloads."
    }
    if protocols.invertsCopyable {
        return "The protocol relaxes Copyable with `~Copyable`. Runtime test doubles record values as escaping `Any`, which requires Copyable payloads."
    }
    if protocols.invertsEscapable {
        return "The protocol relaxes Escapable with `~Escapable`. Runtime test doubles retain recorded values beyond the call, which requires Escapable payloads."
    }
    return "The protocol uses an unknown inverted-protocol constraint. Runtime test doubles require Copyable and Escapable payloads."
}

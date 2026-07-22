import Echo

/// A validated view of an existential's root protocols and their inheritance
/// graphs.
///
/// Protocol witness-table slots are local to the descriptor that declares
/// them, while trampoline dispatch identifiers are dense across the complete
/// inheritance graph. Keeping both coordinates explicit prevents an inherited
/// requirement from accidentally being installed into the root table.
struct ProtocolLayout {
    struct DescriptorID: Hashable {
        let rawValue: UInt

        init(_ descriptor: ProtocolDescriptor) {
            rawValue = UInt(bitPattern: descriptor.ptr)
        }
    }

    struct BaseProtocol {
        let descriptor: ProtocolDescriptor
        let witnessIndex: Int
    }

    /// Stable identity for one getter requirement, scoped to its declaring
    /// protocol's witness table.
    struct GetterRequirementID: Hashable {
        let protocolID: DescriptorID
        let witnessIndex: Int

        init(protocolDescriptor: ProtocolDescriptor, witnessIndex: Int) {
            protocolID = DescriptorID(protocolDescriptor)
            self.witnessIndex = witnessIndex
        }
    }

    struct CallableRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let dispatchIndex: Int
        let kind: StubRequirementKind
        let receiver: StubRequirementReceiver
    }

    struct AssociatedTypeRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let name: String
        let usesReferenceABI: Bool
    }

    struct AssociatedConformanceRequirement {
        let protocolDescriptor: ProtocolDescriptor
        let witnessIndex: Int
        let associatedTypeName: String
        let constraint: ProtocolDescriptor
    }

    /// A `_modify` witness and the ordinary getter/setter dispatch pair that
    /// provides its read and writeback behavior.
    struct ModifyCoroutineRequirement {
        let witnessIndex: Int
        let getterDispatchIndex: Int
        let setterDispatchIndex: Int
        let receiver: StubRequirementReceiver
    }

    enum ReadCoroutineABI: Equatable {
        /// Swift 6.4's source-compatibility witness for the deprecated `read`
        /// spelling. Its `yield_once` ABI is not fabricated by TestDoubles.
        case yieldOnce
        /// Swift 6.3 `read2` and Swift 6.4 `yielding borrow` use the same
        /// `yield_once_2` descriptor ABI supported by the runtime trampoline.
        case yieldOnce2
    }

    /// A physical read witness and the getter-shaped recorder dispatch that
    /// supplies the value borrowed for the duration of the coroutine. Swift
    /// 6.4 maps its paired physical witnesses to one recorder dispatch.
    struct ReadCoroutineRequirement {
        let witnessIndex: Int
        let recorderDispatchIndex: Int
        let receiver: StubRequirementReceiver
        let abi: ReadCoroutineABI
    }

    struct Node {
        let descriptor: ProtocolDescriptor
        let baseProtocols: [BaseProtocol]
        let associatedTypes: [AssociatedTypeRequirement]
        let associatedConformances: [AssociatedConformanceRequirement]
        let callableRequirements: [CallableRequirement]
        let readCoroutineRequirements: [ReadCoroutineRequirement]
        let modifyCoroutineRequirements: [ModifyCoroutineRequirement]
    }

    /// Root protocols in canonical existential-metadata order.
    let roots: [ProtocolDescriptor]
    /// Nodes in base-first, depth-first, first-seen order.
    let nodes: [Node]
    /// Callable requirements in the same flattened order used by explicit APIs.
    let callableRequirements: [CallableRequirement]

    /// Protocols that directly declare one or more callable requirements.
    var declaringNodes: [Node] {
        nodes.filter { $0.callableRequirements.isEmpty == false }
    }

    /// Associated-type accessors in declaring-protocol order after the
    /// inheritance graph has been flattened.
    var associatedTypeRequirements: [AssociatedTypeRequirement] {
        nodes.flatMap(\.associatedTypes)
    }

    func node(for descriptor: ProtocolDescriptor) -> Node? {
        let identifier = DescriptorID(descriptor)
        return nodes.first { DescriptorID($0.descriptor) == identifier }
    }

    static func build(
        roots: [ProtocolDescriptor],
        allowsClassConstraint: Bool = false
    ) throws -> Self {
        var builder = Builder(
            contextName: roots.map(\.name).joined(separator: " & "),
            allowsClassConstraint: allowsClassConstraint
        )
        for root in roots {
            try builder.visit(root)
        }
        return Self(
            roots: roots,
            nodes: builder.nodes,
            callableRequirements: builder.callableRequirements
        )
    }
}

extension ProtocolLayout {
    fileprivate struct Builder {
        typealias LocalModifyRequirement = (
            witnessIndex: Int,
            getterWitnessIndex: Int,
            setterWitnessIndex: Int,
            receiver: StubRequirementReceiver
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
                throw StubError.unsupportedProtocolShape(
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
                            throw StubError.unsupportedProtocolShape(
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
                            throw StubError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "A _modify coroutine is missing its getter or setter dispatch mapping."
                            )
                        }
                        return ModifyCoroutineRequirement(
                            witnessIndex: modifyRequirement.witnessIndex,
                            getterDispatchIndex: getter.dispatchIndex,
                            setterDispatchIndex: setter.dispatchIndex,
                            receiver: modifyRequirement.receiver
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
            // Echo 0.0.4 constructs these arrays with
            // `unsafeUninitializedCapacity`. Its zero-capacity path mutates
            // Swift's shared empty-array storage, which ThreadSanitizer reports
            // when independent stubs are constructed in parallel. Bypass that
            // path for empty metadata and cache non-empty arrays once.
            let localRequirements: [ProtocolRequirement] =
                descriptor.numRequirements == 0 ? [] : descriptor.requirements
            let baseWitnessIndices = localRequirements.enumerated().compactMap {
                index, requirement in
                requirement.flags.kind == .baseProtocol ? index : nil
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
            let associatedTypeWitnessIndices = localRequirements.enumerated().compactMap {
                index, requirement in
                requirement.flags.kind == .associatedTypeAccessFunction ? index : nil
            }
            let associatedConformanceWitnessIndices = localRequirements.enumerated().compactMap {
                index, requirement in
                requirement.flags.kind == .associatedConformanceAccessFunction ? index : nil
            }
            guard associatedTypeNames.count == associatedTypeWitnessIndices.count else {
                throw StubError.unsupportedProtocolShape(
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
                throw StubError.unsupportedProtocolShape(
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
                    throw StubError.unsupportedProtocolShape(
                        protocolName: descriptor.name,
                        reason: "Inherited-protocol metadata is malformed or uses an unsupported constraint."
                    )
                }
                associatedConformances = []
            } else {
                guard dependentConformances.count == associatedConformanceWitnessIndices.count else {
                    throw StubError.unsupportedProtocolShape(
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
                        throw StubError.unsupportedProtocolShape(
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
                switch requirement.flags.kind {
                    case .baseProtocol:
                        guard requirement.flags.isInstance == false else {
                            throw StubError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Inherited-protocol requirement \(index) has invalid flags."
                            )
                        }

                    case .method, .getter:
                        guard let kind = StubRequirementKind(requirement.flags.kind) else {
                            throw StubError.unsupportedProtocolShape(
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
                            let kind = StubRequirementKind(requirement.flags.kind)
                        else {
                            throw StubError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Initializer requirement \(index) has invalid instance flags."
                            )
                        }
                        callableRequirements.append((index, kind, .metatype))

                    case .associatedTypeAccessFunction,
                        .associatedConformanceAccessFunction:
                        guard requirement.flags.isInstance == false else {
                            throw StubError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Associated requirement \(index) has invalid instance flags."
                            )
                        }

                    case .setter:
                        guard index > localRequirements.startIndex,
                            index + 1 < localRequirements.endIndex,
                            localRequirements[index - 1].flags.kind == .getter,
                            localRequirements[index - 1].flags.isInstance == requirement.flags.isInstance,
                            localRequirements[index + 1].flags.kind == .modifyCoroutine,
                            localRequirements[index + 1].flags.isInstance == requirement.flags.isInstance,
                            let kind = StubRequirementKind(requirement.flags.kind)
                        else {
                            throw StubError.unsupportedProtocolShape(
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
                            localRequirements[index - 1].flags.kind == .setter,
                            localRequirements[index - 1].flags.isInstance == requirement.flags.isInstance,
                            localRequirements[index - 2].flags.kind == .getter,
                            localRequirements[index - 2].flags.isInstance == requirement.flags.isInstance
                        else {
                            throw StubError.unsupportedProtocolShape(
                                protocolName: descriptor.name,
                                reason: "Requirement \(index) is an unsupported standalone _modify coroutine."
                            )
                        }
                        modifyCoroutineRequirements.append(
                            (
                                witnessIndex: index,
                                getterWitnessIndex: index - 2,
                                setterWitnessIndex: index - 1,
                                receiver: requirement.flags.isInstance ? .instance : .metatype
                            ))

                    case .readCoroutine:
                        try appendReadCoroutineRequirement(
                            at: index,
                            from: localRequirements,
                            for: descriptor,
                            callableRequirements: &callableRequirements,
                            readCoroutineRequirements: &readCoroutineRequirements
                        )

                    @unknown default:
                        throw StubError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "Requirement \(index) is a \(requirement.flags.kind). Only inherited protocols, initializers, methods, ordinary getters, and direct property setters are supported."
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

        private func validatedSignatureConstraints(
            _ signature: [GenericRequirementDescriptor],
            for descriptor: ProtocolDescriptor
        ) throws -> (
            conformances: [GenericRequirementDescriptor],
            classLayouts: [GenericRequirementDescriptor]
        ) {
            let conformances = signature.filter {
                genericRequirementKindCode($0) == 0
            }
            let classLayouts = signature.filter {
                genericRequirementKindCode($0) == 0x1f
            }
            let invertedProtocols = signature.filter {
                genericRequirementKindCode($0) == 5
            }
            guard
                conformances.count + classLayouts.count
                    + invertedProtocols.count == signature.count
            else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Only inherited-protocol, associated-type conformance, and class-layout constraints are supported."
                )
            }
            if let requirement = invertedProtocols.first {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: invertedProtocolDiagnostic(for: requirement)
                )
            }
            return (conformances, classLayouts)
        }

        private func appendReadCoroutineRequirement(
            at index: Int,
            from localRequirements: [ProtocolRequirement],
            for descriptor: ProtocolDescriptor,
            callableRequirements: inout [LocalCallableRequirement],
            readCoroutineRequirements: inout [LocalReadRequirement]
        ) throws {
            let requirement = localRequirements[index]
            let receiver: StubRequirementReceiver =
                requirement.flags.isInstance ? .instance : .metatype
            let usesYieldOnce2 = requirement.flags.bits & 0x20 != 0
            if usesYieldOnce2,
                index > localRequirements.startIndex,
                localRequirements[index - 1].flags.kind == .readCoroutine,
                localRequirements[index - 1].flags.bits & 0x20 == 0
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
                localRequirements[pairedIndex].flags.kind == .readCoroutine,
                localRequirements[pairedIndex].flags.bits & 0x20 != 0,
                localRequirements[pairedIndex].flags.isInstance
                    == requirement.flags.isInstance
            else {
                throw StubError.unsupportedProtocolShape(
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
                    genericRequirementLayoutKindCode($0) == 0
                })
            else {
                throw StubError.unsupportedProtocolShape(
                    protocolName: descriptor.name,
                    reason: "Only the AnyObject class layout constraint is supported."
                )
            }
            let selfRequirements = requirements.filter(constrainsProtocolSelf)
            guard selfRequirements.count <= 1,
                selfRequirements.isEmpty || allowsClassConstraint
            else {
                throw StubError.unsupportedProtocolShape(
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
                        throw StubError.unsupportedProtocolShape(
                            protocolName: descriptor.name,
                            reason: "A class-layout constraint does not identify a declared associated type."
                        )
                    }
                    return identity.name
                }
            guard Set(constrainedAssociatedTypeNames).count == constrainedAssociatedTypeNames.count else {
                throw StubError.unsupportedProtocolShape(
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

private func genericRequirementKindCode(
    _ requirement: GenericRequirementDescriptor
) -> UInt8 {
    // Echo 0.0.4 force-unwraps its enum. Read the stable flags word first so a
    // newer requirement kind is rejected rather than trapping in the library.
    let pointer = unsafeBitCast(requirement, to: UnsafeRawPointer.self)
    return UInt8(pointer.load(as: UInt32.self) & 0x1f)
}

private func genericRequirementLayoutKindCode(
    _ requirement: GenericRequirementDescriptor
) -> UInt32 {
    // The requirement payload follows the flags and relative parameter-name
    // pointer. Reading the raw stable ABI value avoids Echo force-unwrapping a
    // newer layout-kind enum before this parser can reject it.
    let pointer = unsafeBitCast(requirement, to: UnsafeRawPointer.self)
    return pointer.load(fromByteOffset: 8, as: UInt32.self)
}

private func invertedProtocolDiagnostic(
    for requirement: GenericRequirementDescriptor
) -> String {
    let pointer = unsafeBitCast(requirement, to: UnsafeRawPointer.self)
    // The InvertedProtocols payload stores a UInt16 generic-parameter index,
    // followed by Swift's ABI-defined Copyable/Escapable bitset.
    let protocols = pointer.load(fromByteOffset: 10, as: UInt16.self)
    let copyable = protocols & 0x1 != 0
    let escapable = protocols & 0x2 != 0
    if copyable, escapable {
        return "The protocol relaxes Copyable and Escapable with `~Copyable` and `~Escapable`. Runtime test doubles record escaping `Any` values, which require copyable, escapable payloads."
    }
    if copyable {
        return "The protocol relaxes Copyable with `~Copyable`. Runtime test doubles record values as escaping `Any`, which requires Copyable payloads."
    }
    if escapable {
        return "The protocol relaxes Escapable with `~Escapable`. Runtime test doubles retain recorded values beyond the call, which requires Escapable payloads."
    }
    return "The protocol uses an unknown inverted-protocol constraint. Runtime test doubles require Copyable and Escapable payloads."
}

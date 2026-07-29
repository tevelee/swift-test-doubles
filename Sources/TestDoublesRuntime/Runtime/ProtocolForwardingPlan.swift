import CTestDoublesTrampoline
import Echo
import TestDoublesRuntimeMetadata
import TestDoublesRuntimeSupport

struct ForwardedCallPlan: @unchecked Sendable {
    let function: UnsafeRawPointer
    let selfValue: UnsafeRawPointer
    let witnessTable: UnsafeRawPointer
    /// Where the target's metadata/witness-table pair each independently
    /// land -- a register, or a spill to the outgoing stack -- mirroring
    /// whatever the real target witness's own competitive register
    /// allocation produced. `nil` only for an async call using
    /// `asyncStackPlan` instead.
    let dynamicSelfLocations: WitnessCallTransportPlan.DynamicSelfLocations?
    /// Ordered outgoing-stack-word sources `td_swift_invoke_witness` must
    /// copy to the real call: spilled visible arguments (read from the
    /// incoming frame) interleaved with a spilled metadata or witness-table
    /// pointer (computed fresh, never read from the frame), in the same
    /// order the target's own incoming stack expects them. Always empty for
    /// an async call.
    let outgoingStackSources: [WitnessCallTransportPlan.OutgoingStackSource]
    let asyncStackPlan: AsyncForwardingStackPlan?
    let isAsync: Bool
}

struct ForwardedReadPlan: @unchecked Sendable {
    let entry: UnsafeRawPointer
    let descriptorSlot: UnsafeRawPointer
    let declarationDiscriminator: UInt16
    let resumeDiscriminator: UInt16
    let selfValue: UnsafeRawPointer
    let witnessTable: UnsafeRawPointer
    let hiddenArgumentIndex: Int
    let callerFrameSize: Int
    let resultIsIndirect: Bool
}

struct ForwardedModifyPlan: @unchecked Sendable {
    let entry: UnsafeRawPointer
    let entrySlot: UnsafeRawPointer
    let declarationDiscriminator: UInt16
    let resumeDiscriminator: UInt16?
    let selfValue: UnsafeRawPointer
    let witnessTable: UnsafeRawPointer
    let hiddenArgumentIndex: Int
    let callerFrameSize: Int
    let abi: ProtocolLayout.ModifyCoroutineABI
}

struct ProtocolForwardingPlans: @unchecked Sendable {
    let calls: [Int: ForwardedCallPlan]
    let reads: [Int: ForwardedReadPlan]
    let modifications: [Int: ForwardedModifyPlan]
}

struct ProtocolForwardingPlanBuilder<P> {
    let target: ForwardingTarget<P>
    let methods: [MethodDescriptor]
    let layout: ProtocolLayout

    func build() throws -> ProtocolForwardingPlans {
        var readRequirements: [Int: ProtocolLayout.ReadCoroutineRequirement] = [:]
        var modifyRequirements: [Int: ProtocolLayout.ModifyCoroutineRequirement] = [:]
        for node in layout.nodes {
            for requirement in try Self.validatedReadRequirements(
                node.readCoroutineRequirements,
                protocolName: node.descriptor.name
            ) {
                guard
                    readRequirements[requirement.recorderDispatchIndex] == nil
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: node.descriptor.name,
                        reason:
                            "Multiple yielding-borrow read witnesses map to recorder dispatch \(requirement.recorderDispatchIndex)."
                    )
                }
                readRequirements[requirement.recorderDispatchIndex] = requirement
            }
            for requirement in node.modifyCoroutineRequirements {
                modifyRequirements[requirement.getterDispatchIndex] = requirement
            }
        }

        var calls: [Int: ForwardedCallPlan] = [:]
        var modifications: [Int: ForwardedModifyPlan] = [:]
        var reads: [Int: ForwardedReadPlan] = [:]
        for method in methods {
            // An initializer's `Self` result must retain the fabricated
            // existential metadata and witness tables used by the caller.
            // It can be explicitly overridden with `when(initializer:)`, but
            // cannot safely return the forwarding target's distinct type.
            if method.kind == .initializer {
                continue
            }
            let requirement = layout.callableRequirements[method.index]
            let protocolName = requirement.protocolDescriptor.name
            try validate(method, protocolName: protocolName)

            let identifier = ProtocolLayout.DescriptorID(
                requirement.protocolDescriptor
            )
            guard let witnessTable = target.witnessTables[identifier] else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason: "The forwarding target is missing a witness table for requirement \(method.index)."
                )
            }
            let witnessSlot =
                witnessTable.ptr
                + (1 + method.witnessIndex) * MemoryLayout<UInt>.size
            let signedFunction = witnessSlot.load(as: UnsafeRawPointer.self)

            if let modifyRequirement = modifyRequirements[method.index] {
                modifications[method.index] = try makeModifyPlan(
                    method: method,
                    requirement: requirement,
                    modifyRequirement: modifyRequirement,
                    witnessTable: witnessTable,
                    protocolName: protocolName
                )
            }

            if let readRequirement = readRequirements[method.index] {
                reads[method.index] = try makeReadPlan(
                    method: method,
                    requirement: requirement,
                    readRequirement: readRequirement,
                    witnessTable: witnessTable,
                    witnessSlot: witnessSlot,
                    signedFunction: signedFunction,
                    protocolName: protocolName
                )
                continue
            }

            calls[method.index] = try makeCallPlan(
                method: method,
                signedFunction: signedFunction,
                witnessTable: witnessTable,
                protocolName: protocolName
            )
        }
        return ProtocolForwardingPlans(
            calls: calls,
            reads: reads,
            modifications: modifications
        )
    }

    static func validatedReadRequirements(
        _ requirements: [ProtocolLayout.ReadCoroutineRequirement],
        protocolName: String
    ) throws -> [ProtocolLayout.ReadCoroutineRequirement] {
        for legacy in requirements where legacy.abi == .yieldOnce {
            guard
                requirements.contains(where: {
                    $0.abi == .yieldOnce2
                        && $0.witnessIndex == legacy.witnessIndex + 1
                        && $0.recorderDispatchIndex
                            == legacy.recorderDispatchIndex
                        && $0.receiver.rawValue == legacy.receiver.rawValue
                })
            else {
                throw RuntimeConstructionError.unsupportedProtocolShape(
                    protocolName: protocolName,
                    reason:
                        "The legacy read witness at index \(legacy.witnessIndex) is missing its adjacent yielding-borrow witness for recorder dispatch \(legacy.recorderDispatchIndex)."
                )
            }
        }
        return requirements.filter { $0.abi == .yieldOnce2 }
    }

    private func validate(
        _ method: MethodDescriptor,
        protocolName: String
    ) throws {
        guard method.kind != .initializer else {
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .nonInstanceRequirement(index: method.index)
            )
        }
        try validateDynamicSelfBoundary(method, protocolName: protocolName)
        let concreteTypes = method.argumentTypes + [method.returnType]
        if let reason = runtimeSIMDUnsupportedReason(for: method) {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
        if let reason = runtimeMethodGenericParameterForwardingUnsupportedReason(for: method) {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: reason
            )
        }
        guard method.typedWitnessAdapterFactory == nil,
            concreteTypes.allSatisfy({ !isRuntimeFunctionType($0) })
        else {
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .functionValues(index: method.index)
            )
        }
    }

    private func makeModifyPlan(
        method: MethodDescriptor,
        requirement: ProtocolLayout.CallableRequirement,
        modifyRequirement: ProtocolLayout.ModifyCoroutineRequirement,
        witnessTable: WitnessTable,
        protocolName: String
    ) throws -> ForwardedModifyPlan {
        guard method.kind == .getter,
            method.receiver == modifyRequirement.receiver,
            method.isAsync == false,
            method.isThrowing == false,
            method.typedWitnessAdapterFactory == nil,
            method.arguments.allSatisfy({ $0.ownership == .borrowed })
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason:
                    "The _modify requirement at witness index \(modifyRequirement.witnessIndex) is outside the supported synchronous, nonthrowing borrowed-value forwarding ABI."
            )
        }
        let modifyWitnessSlot =
            witnessTable.ptr
            + (1 + modifyRequirement.witnessIndex) * MemoryLayout<UInt>.size
        let signedEntry = modifyWitnessSlot.load(as: UnsafeRawPointer.self)
        let flags = requirement.protocolDescriptor.requirements[
            modifyRequirement.witnessIndex
        ].flags
        let declarationDiscriminator = flags.extraDiscriminator
        let entry: UnsafeRawPointer
        let resumeDiscriminator: UInt16?
        let callerFrameSize: Int
        switch modifyRequirement.abi {
            case .yieldOnce:
                entry = signedEntry
                resumeDiscriminator = nil
                callerFrameSize = 32

            case .yieldOnce2:
                var descriptorTarget = TDCoroWitnessTarget()
                guard
                    td_prepare_coro_witness_target(
                        signedEntry,
                        UnsafeRawPointer(modifyWitnessSlot),
                        declarationDiscriminator,
                        &descriptorTarget
                    ),
                    let descriptorEntry = descriptorTarget.entry,
                    descriptorTarget.callerFrameSize == 32,
                    let discriminator =
                        YieldingAccessorRuntime.modifyResumeDiscriminator(for: method)
                else {
                    throw RuntimeConstructionError.unsupportedProtocolShape(
                        protocolName: protocolName,
                        reason:
                            "The forwarding target's _modify witness at index \(modifyRequirement.witnessIndex) is not a supported yield_once_2 descriptor with a 32-byte caller frame."
                    )
                }
                entry = descriptorEntry
                resumeDiscriminator = discriminator
                callerFrameSize = Int(descriptorTarget.callerFrameSize)
        }
        #if arch(x86_64)
            let descriptorArgumentOffset = 2
        #else
            let descriptorArgumentOffset = 1
        #endif
        return try ForwardedModifyPlan(
            entry: entry,
            entrySlot: UnsafeRawPointer(modifyWitnessSlot),
            declarationDiscriminator: declarationDiscriminator,
            resumeDiscriminator: resumeDiscriminator,
            selfValue: target.receiverValue(for: method),
            witnessTable: witnessTable.ptr,
            hiddenArgumentIndex: hiddenArgumentIndex(
                for: method,
                protocolName: protocolName,
                initialGeneralPurposeOffset:
                    modifyRequirement.abi == .yieldOnce2
                    ? descriptorArgumentOffset : 1
            ),
            callerFrameSize: callerFrameSize,
            abi: modifyRequirement.abi
        )
    }

    private func makeReadPlan(
        method: MethodDescriptor,
        requirement: ProtocolLayout.CallableRequirement,
        readRequirement: ProtocolLayout.ReadCoroutineRequirement,
        witnessTable: WitnessTable,
        witnessSlot: UnsafeRawPointer,
        signedFunction: UnsafeRawPointer,
        protocolName: String
    ) throws -> ForwardedReadPlan {
        guard method.kind == .getter,
            method.receiver == readRequirement.receiver,
            method.isAsync == false,
            method.isThrowing == false,
            method.arguments.allSatisfy({ $0.ownership == .borrowed }),
            let resumeDiscriminator =
                YieldingAccessorRuntime.readResumeDiscriminator(for: method)
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason:
                    "The read requirement at witness index \(readRequirement.witnessIndex) is outside the supported synchronous, nonthrowing borrowed-value forwarding ABI."
            )
        }
        let flags = requirement.protocolDescriptor.requirements[
            method.witnessIndex
        ].flags
        let declarationDiscriminator = flags.extraDiscriminator
        var descriptorTarget = TDCoroWitnessTarget()
        guard
            td_prepare_coro_witness_target(
                signedFunction,
                UnsafeRawPointer(witnessSlot),
                declarationDiscriminator,
                &descriptorTarget
            ),
            let entry = descriptorTarget.entry,
            descriptorTarget.callerFrameSize == 32
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason:
                    "The forwarding target's read witness at index \(readRequirement.witnessIndex) is not a supported Swift 6.3 yield_once_2 descriptor with a 32-byte caller frame."
            )
        }
        #if arch(x86_64)
            let initialGeneralPurposeOffset = 2
        #else
            let initialGeneralPurposeOffset = 1
        #endif
        return try ForwardedReadPlan(
            entry: entry,
            descriptorSlot: UnsafeRawPointer(witnessSlot),
            declarationDiscriminator: declarationDiscriminator,
            resumeDiscriminator: resumeDiscriminator,
            selfValue: target.selfValue,
            witnessTable: witnessTable.ptr,
            hiddenArgumentIndex: hiddenArgumentIndex(
                for: method,
                protocolName: protocolName,
                initialGeneralPurposeOffset: initialGeneralPurposeOffset
            ),
            callerFrameSize: Int(descriptorTarget.callerFrameSize),
            resultIsIndirect: {
                if case .indirect = method.result.layout { return true }
                return false
            }()
        )
    }

    private func makeCallPlan(
        method: MethodDescriptor,
        signedFunction: UnsafeRawPointer,
        witnessTable: WitnessTable,
        protocolName: String
    ) throws -> ForwardedCallPlan {
        let asyncTransport =
            method.isAsync
            ? WitnessCallTransportPlan(
                method: method,
                trailingPayload: .dynamicSelf
            )
            : nil
        let asyncStackPlan =
            method.isAsync
            ? asyncForwardingStackPlan(
                for: method,
                architecture: .current
            )
            : nil
        if let asyncTransport,
            asyncTransport.stackByteCount > 0,
            asyncStackPlan == nil
        {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: unsupportedAsyncForwardingEgressDiagnostic(
                    architecture: .current
                )
            )
        }
        // Only a genuinely synchronous call goes through td_swift_invoke_witness,
        // the routine able to carry outgoing stack words. An async call either
        // fits asyncStackPlan's bounded multiword model or remains register-only.
        let (dynamicSelfLocations, outgoingStackSources): (WitnessCallTransportPlan.DynamicSelfLocations?, [WitnessCallTransportPlan.OutgoingStackSource]) =
            if asyncStackPlan == nil {
                try dynamicSelfTransport(for: method, protocolName: protocolName)
            } else {
                (nil, [])
            }
        let function =
            if method.isAsync {
                td_strip_async_witness_pointer(signedFunction)
            } else {
                td_strip_witness_function_pointer(signedFunction)
            }
        guard let function else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: protocolName,
                reason: "The forwarding target has a null witness for requirement \(method.index)."
            )
        }
        return ForwardedCallPlan(
            function: function,
            selfValue: target.receiverValue(for: method),
            witnessTable: witnessTable.ptr,
            dynamicSelfLocations: dynamicSelfLocations,
            outgoingStackSources: outgoingStackSources,
            asyncStackPlan: asyncStackPlan,
            isAsync: method.isAsync
        )
    }

    /// - Note: metadata and witness table are **not** reserved a fixed
    ///   register pair here. Each independently lands wherever the target's
    ///   own competitive register allocation puts it -- a register, or a
    ///   spill to the outgoing stack -- exactly matching the real target
    ///   witness function's compiled calling convention. See
    ///   `WitnessCallTransportPlan.directForwardingOutgoingStackSources`.
    private func dynamicSelfTransport(
        for method: MethodDescriptor,
        protocolName: String
    ) throws -> (WitnessCallTransportPlan.DynamicSelfLocations?, [WitnessCallTransportPlan.OutgoingStackSource]) {
        let transport = WitnessCallTransportPlan(
            method: method,
            trailingPayload: .dynamicSelf
        )
        guard let sources = transport.directForwardingOutgoingStackSources else {
            let limit = WitnessCallTransportPlan.maximumOutgoingStackWords
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .outgoingStackWords(
                    index: method.index,
                    limit: limit
                )
            )
        }
        return (transport.dynamicSelfLocations, sources)
    }

    private func validateDynamicSelfBoundary(
        _ method: MethodDescriptor,
        protocolName: String
    ) throws {
        guard method.returnConvention != .selfType,
            method.returnConvention != .optionalSelf
        else {
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .dynamicSelfResult(index: method.index)
            )
        }
        guard
            method.arguments.allSatisfy({
                $0.value.convention != .selfType
                    && $0.value.convention != .optionalSelf
            })
        else {
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .selfArguments(index: method.index)
            )
        }
    }

    private func hiddenArgumentIndex(
        for method: MethodDescriptor,
        protocolName: String,
        initialGeneralPurposeOffset: Int = 0
    ) throws -> Int {
        let transport = WitnessCallTransportPlan(
            method: method,
            initialGeneralPurposeOffset: initialGeneralPurposeOffset,
            trailingPayload: .dynamicSelf
        )
        guard
            let hiddenArgumentIndex =
                transport.directForwardingHiddenArgumentIndex
        else {
            throw RuntimeConstructionError.forwardingUnsupported(
                protocolName: protocolName,
                reason: .hiddenArguments(index: method.index)
            )
        }
        return hiddenArgumentIndex
    }
}

import Echo

package struct YieldOnce2WitnessPlan {
    package let resumeDiscriminator: UInt16
}

/// Selects ABI trampolines from prepared runtime method plans. The semantic
/// endpoint is opaque: an invocation without a method plan can still fabricate
/// an ordinary callable trampoline, whose first call is rejected by the
/// endpoint.
package struct FabricatedWitnessDispatch {
    package let invocation: RuntimeFabricatedInvocation

    package init(invocation: RuntimeFabricatedInvocation) {
        self.invocation = invocation
    }

    func makeCallableTrampoline(
        for requirement: ProtocolLayout.CallableRequirement,
        in node: ProtocolLayout.Node,
        witnessTable: UnsafeMutableRawPointer,
        resources: FabricatedRuntimeResources
    ) throws -> UnsafeRawPointer {
        let trampoline: UnsafeRawPointer?
        if let method = invocation.method(at: requirement.dispatchIndex) {
            trampoline =
                if let factory = method.descriptor.typedWitnessAdapterFactory {
                    resources.makeTypedTrampoline(
                        factory: factory,
                        endpoint: invocation.endpoint,
                        method: method.descriptor
                    )
                } else {
                    resources.makeTrampoline(
                        kind: method.descriptor.isAsync ? .asynchronous : .synchronous,
                        slot: method.descriptor.index,
                        context: UnsafeRawPointer(witnessTable)
                    )
                }
        } else {
            let flags = requirement.protocolDescriptor
                .requirements[requirement.witnessIndex].flags
            trampoline = resources.makeTrampoline(
                kind: flags.isAsync ? .asynchronous : .synchronous,
                slot: requirement.dispatchIndex,
                context: UnsafeRawPointer(witnessTable)
            )
        }

        guard let trampoline else {
            throw RuntimeConstructionError.trampolineAllocationFailed(
                requirementIndex: requirement.dispatchIndex
            )
        }
        return trampoline
    }

    func readPlan(
        for requirement: ProtocolLayout.ReadCoroutineRequirement,
        in node: ProtocolLayout.Node
    ) throws -> YieldOnce2WitnessPlan {
        precondition(requirement.abi == .yieldOnce2)
        guard let method = invocation.method(at: requirement.recorderDispatchIndex)?.descriptor
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: node.descriptor.name,
                reason:
                    "The runtime invocation endpoint cannot fabricate the result-dependent resume ABI for the read requirement at witness index \(requirement.witnessIndex)."
            )
        }
        guard method.kind == .getter,
            method.receiver == requirement.receiver,
            method.isAsync == false,
            method.isThrowing == false,
            method.typedWitnessAdapterFactory == nil,
            method.arguments.allSatisfy({ $0.ownership == .borrowed }),
            method.returnConvention != .selfType,
            method.returnConvention != .optionalSelf,
            reflect(method.returnType).kind != .function,
            let resumeDiscriminator = YieldingAccessorRuntime.readResumeDiscriminator(for: method)
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: node.descriptor.name,
                reason:
                    "The read requirement at witness index \(requirement.witnessIndex) is outside the supported synchronous, nonthrowing borrowed-value ABI. "
                    + "Function, dynamic Self, typed-adapter, and result layouts whose resume discriminator cannot be derived require a hand-written test double."
            )
        }
        return YieldOnce2WitnessPlan(resumeDiscriminator: resumeDiscriminator)
    }

    func modifyPlan(
        for requirement: ProtocolLayout.ModifyCoroutineRequirement,
        in node: ProtocolLayout.Node
    ) throws -> YieldOnce2WitnessPlan {
        precondition(requirement.abi == .yieldOnce2)
        guard let method = invocation.method(at: requirement.getterDispatchIndex)?.descriptor
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: node.descriptor.name,
                reason:
                    "The runtime invocation endpoint cannot fabricate the result-dependent resume ABI for the _modify requirement at witness index \(requirement.witnessIndex)."
            )
        }
        guard method.kind == .getter,
            method.receiver == requirement.receiver,
            method.isAsync == false,
            method.isThrowing == false,
            method.typedWitnessAdapterFactory == nil,
            method.arguments.allSatisfy({ $0.ownership == .borrowed }),
            method.returnConvention != .selfType,
            method.returnConvention != .optionalSelf,
            reflect(method.returnType).kind != .function,
            let resumeDiscriminator = YieldingAccessorRuntime.modifyResumeDiscriminator(for: method)
        else {
            throw RuntimeConstructionError.unsupportedProtocolShape(
                protocolName: node.descriptor.name,
                reason:
                    "The _modify requirement at witness index \(requirement.witnessIndex) is outside the supported synchronous, nonthrowing yield_once_2 ABI."
            )
        }
        return YieldOnce2WitnessPlan(resumeDiscriminator: resumeDiscriminator)
    }
}

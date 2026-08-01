import CTestDoublesTrampoline
import TestDoublesRuntimeMetadata

package protocol RuntimeForwarding: AnyObject, Sendable {
    func forward(_ method: PreparedRuntimeMethod, frame: TrampolineCallFrame)
    func makeModifyState(
        for method: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState
    func makeReadState(
        for method: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState
    func makeAsyncState(
        for method: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState
}

package final class ProtocolForwarder<P>: RuntimeForwarding, @unchecked Sendable {
    private let target: ForwardingTarget<P>
    private let plans: ProtocolForwardingPlans

    package init(
        target: ForwardingTarget<P>,
        methods: [MethodDescriptor],
        layout: ProtocolLayout
    ) throws {
        self.target = target
        plans = try ProtocolForwardingPlanBuilder(
            target: target,
            methods: methods,
            layout: layout
        ).build()
    }

    package func forward(_ runtimeMethod: PreparedRuntimeMethod, frame: TrampolineCallFrame) {
        let plan = prepareCall(runtimeMethod, frame: frame)
        precondition(
            plan.isAsync == false,
            "[TestDoubles] An async forwarding requirement entered synchronous transport."
        )
        precondition(
            plan.outgoingStackSources.count
                <= WitnessCallTransportPlan.maximumOutgoingStackWords,
            "[TestDoubles] A forwarding plan exceeded its outgoing stack word ceiling."
        )
        let words = plan.outgoingStackSources.map { source -> UInt64 in
            switch source {
                case .argument(let location):
                    frame.scalarBits(at: location)
                case .metadata:
                    UInt64(UInt(bitPattern: target.metadata))
                case .witnessTable:
                    UInt64(UInt(bitPattern: plan.witnessTable))
            }
        }
        td_swift_invoke_witness(
            plan.function,
            plan.selfValue,
            frame.pointer,
            words.count > 0 ? words[0] : 0,
            words.count > 1 ? words[1] : 0,
            words.count > 2 ? words[2] : 0,
            words.count > 3 ? words[3] : 0,
            words.count > 4 ? words[4] : 0,
            words.count > 5 ? words[5] : 0,
            words.count > 6 ? words[6] : 0,
            words.count > 7 ? words[7] : 0
        )
    }

    package func makeReadState(
        for runtimeMethod: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState {
        let method = runtimeMethod.descriptor
        guard let plan = plans.reads[method.index] else {
            preconditionFailure(
                "[TestDoubles] No read forwarding plan exists for requirement \(method.index)."
            )
        }
        #if arch(x86_64)
            let initialGeneralPurposeOffset = 2
        #else
            let initialGeneralPurposeOffset = 1
        #endif
        let calibratedPlan = ForwardedReadPlan(
            entry: plan.entry,
            descriptorSlot: plan.descriptorSlot,
            declarationDiscriminator: plan.declarationDiscriminator,
            resumeDiscriminator: plan.resumeDiscriminator,
            selfValue: plan.selfValue,
            witnessTable: plan.witnessTable,
            hiddenArgumentIndex:
                runtimeMethod.coroutineDynamicSelfHiddenArgumentIndex(
                    initialGeneralPurposeOffset: initialGeneralPurposeOffset
                ),
            callerFrameSize: plan.callerFrameSize,
            resultIsIndirect: plan.resultIsIndirect
        )
        return ForwardedReadState(
            owner: self,
            plan: calibratedPlan,
            metadata: target.metadata,
            frame: frame
        )
    }

    package func makeModifyState(
        for runtimeMethod: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState {
        let method = runtimeMethod.descriptor
        guard let plan = plans.modifications[method.index] else {
            preconditionFailure(
                "[TestDoubles] No _modify forwarding plan exists for requirement \(method.index)."
            )
        }
        #if arch(x86_64)
            let descriptorArgumentOffset = 2
        #else
            let descriptorArgumentOffset = 1
        #endif
        let initialGeneralPurposeOffset =
            plan.abi == .yieldOnce2 ? descriptorArgumentOffset : 1
        let calibratedPlan = ForwardedModifyPlan(
            entry: plan.entry,
            entrySlot: plan.entrySlot,
            declarationDiscriminator: plan.declarationDiscriminator,
            resumeDiscriminator: plan.resumeDiscriminator,
            selfValue: plan.selfValue,
            witnessTable: plan.witnessTable,
            hiddenArgumentIndex:
                runtimeMethod.coroutineDynamicSelfHiddenArgumentIndex(
                    initialGeneralPurposeOffset: initialGeneralPurposeOffset
                ),
            callerFrameSize: plan.callerFrameSize,
            abi: plan.abi
        )
        return ForwardedModifyState(
            owner: self,
            plan: calibratedPlan,
            metadata: target.metadata,
            frame: frame
        )
    }

    package func makeAsyncState(
        for runtimeMethod: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState {
        let method = runtimeMethod.descriptor
        let plan = prepareCall(runtimeMethod, frame: frame)
        precondition(
            plan.isAsync,
            "[TestDoubles] A synchronous forwarding requirement entered async transport."
        )
        return ForwardedAsyncState(
            owner: self,
            plan: plan,
            metadata: target.metadata,
            isThrowing: method.isThrowing,
            frame: frame
        )
    }

    private func prepareCall(
        _ runtimeMethod: PreparedRuntimeMethod,
        frame: TrampolineCallFrame
    ) -> ForwardedCallPlan {
        let method = runtimeMethod.descriptor
        guard let basePlan = plans.calls[method.index] else {
            preconditionFailure(
                "[TestDoubles] No forwarding plan exists for requirement \(method.index)."
            )
        }
        let transport = WitnessCallTransportPlan(
            method: method,
            argumentLayouts: runtimeMethod.argumentLayouts,
            trailingPayload: .dynamicSelf
        )
        let asyncStackPlan =
            method.isAsync
            ? asyncForwardingStackPlan(
                for: method,
                argumentLayouts: runtimeMethod.argumentLayouts,
                architecture: .current
            )
            : nil
        let dynamicSelfLocations: WitnessCallTransportPlan.DynamicSelfLocations?
        let outgoingStackSources: [WitnessCallTransportPlan.OutgoingStackSource]
        if asyncStackPlan == nil {
            guard let sources = transport.directForwardingOutgoingStackSources else {
                preconditionFailure(
                    "[TestDoubles] Calibrated forwarding for requirement \(method.index) "
                        + "exceeded its outgoing stack transport boundary."
                )
            }
            dynamicSelfLocations = transport.dynamicSelfLocations
            outgoingStackSources = sources
        } else {
            dynamicSelfLocations = nil
            outgoingStackSources = []
        }
        let plan = ForwardedCallPlan(
            function: basePlan.function,
            selfValue: basePlan.selfValue,
            witnessTable: basePlan.witnessTable,
            dynamicSelfLocations: dynamicSelfLocations,
            outgoingStackSources: outgoingStackSources,
            asyncStackPlan: asyncStackPlan,
            isAsync: basePlan.isAsync
        )
        // Metadata and witness table each independently land in a register
        // or spill to the outgoing stack -- whichever one the target's own
        // competitive register allocation produced. Register-located values
        // are written here; stack-located ones are carried by `forward()`'s
        // outgoingStackSources instead.
        if let locations = plan.dynamicSelfLocations {
            if case .generalPurposeRegister(let index) = locations.metadata.storage {
                frame.storeGeneralPurposeArgument(
                    UInt(bitPattern: target.metadata),
                    at: index
                )
            }
            if case .generalPurposeRegister(let index) = locations.witnessTable.storage {
                frame.storeGeneralPurposeArgument(
                    UInt(bitPattern: plan.witnessTable),
                    at: index
                )
            }
        } else {
            precondition(
                method.isAsync && plan.asyncStackPlan != nil,
                "[TestDoubles] A forwarding target has no hidden-argument transport plan."
            )
        }
        return plan
    }
}

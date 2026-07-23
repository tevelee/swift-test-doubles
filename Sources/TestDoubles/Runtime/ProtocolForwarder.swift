import CTestDoublesTrampoline

protocol ProtocolForwarding: AnyObject, Sendable {
    func forward(_ method: MethodDescriptor, frame: TrampolineCallFrame)
    func makeModifyState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState
    func makeReadState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState
    func makeAsyncState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState
}

final class ProtocolForwarder<P>: ProtocolForwarding, @unchecked Sendable {
    private let target: ForwardingTarget<P>
    private let plans: ProtocolForwardingPlans

    init(
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

    func forward(_ method: MethodDescriptor, frame: TrampolineCallFrame) {
        let plan = prepareCall(method, frame: frame)
        precondition(
            plan.isAsync == false,
            "[TestDoubles] An async Spy requirement entered synchronous forwarding."
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
            words.count > 1 ? words[1] : 0
        )
    }

    func makeReadState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState {
        guard let plan = plans.reads[method.index] else {
            preconditionFailure(
                "[TestDoubles] No read forwarding plan exists for Spy requirement \(method.index)."
            )
        }
        return ForwardedReadState(
            owner: self,
            plan: plan,
            metadata: target.metadata,
            frame: frame
        )
    }

    func makeModifyState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any YieldingAccessorState {
        guard let plan = plans.modifications[method.index] else {
            preconditionFailure(
                "[TestDoubles] No _modify forwarding plan exists for Spy requirement \(method.index)."
            )
        }
        return ForwardedModifyState(
            owner: self,
            plan: plan,
            metadata: target.metadata,
            frame: frame
        )
    }

    func makeAsyncState(
        for method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> any AsyncTrampolineDispatchState {
        let plan = prepareCall(method, frame: frame)
        precondition(
            plan.isAsync,
            "[TestDoubles] A synchronous Spy requirement entered async forwarding."
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
        _ method: MethodDescriptor,
        frame: TrampolineCallFrame
    ) -> ForwardedCallPlan {
        guard let plan = plans.calls[method.index] else {
            preconditionFailure(
                "[TestDoubles] No forwarding plan exists for Spy requirement \(method.index)."
            )
        }
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

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
        td_swift_invoke_witness(plan.function, plan.selfValue, frame.pointer)
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
        if let hiddenArgumentIndex = plan.hiddenArgumentIndex {
            frame.storeGeneralPurposeArgument(
                UInt(bitPattern: target.metadata),
                at: hiddenArgumentIndex
            )
            frame.storeGeneralPurposeArgument(
                UInt(bitPattern: plan.witnessTable),
                at: hiddenArgumentIndex + 1
            )
        } else {
            precondition(
                method.isAsync && plan.asyncStackPlan != nil,
                "[TestDoubles] A forwarding target has no hidden-argument transport plan."
            )
        }
        return plan
    }
}

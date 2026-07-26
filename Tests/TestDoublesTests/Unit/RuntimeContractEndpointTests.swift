import InternalRuntimeContract
import Testing
@testable import TestDoubles

@Suite struct RuntimeContractEndpointTests {
    @Test func semanticMethodProjectionDrivesForwardingAndCapture() {
        let recorder = StubRecorder(
            methods: [method(slot: 0, name: "load()")],
            allowsForwardingFallback: true
        )
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)

        #expect(endpoint.invocationMode == .normal)
        _ = recorder.captureCalls {
            #expect(endpoint.invocationMode == .capturing)
        }

        let dispatch = endpoint.prepareDispatch(
            RuntimeInvocationRequest(slot: 0, arguments: [])
        )
        if case .forwarding = dispatch {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }

    @Test func semanticDynamicSelfAndAccessorPairingStayInTheContract() {
        let getter = method(
            slot: 0,
            name: "copy()",
            kind: .getter,
            resultConvention: .selfType
        )
        let setter = method(
            slot: 1,
            name: "copy(_:)",
            kind: .setter,
            resultConvention: .concrete
        )
        let recorder = StubRecorder(
            methods: [getter, setter],
            modifyDispatchDescriptors: [
                0: RuntimeModifyDispatch(getterSlot: 0, setterSlot: 1)
            ]
        )
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)

        if case .payload = endpoint.recordingResult(at: 0) {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
        #expect(endpoint.modifyDispatch(forGetterSlot: 0)?.getterSlot == 0)
        #expect(endpoint.modifyDispatch(forGetterSlot: 0)?.setterSlot == 1)
    }

    @Test func semanticAssociatedTypeUseRetainsOrderedNamesOnly() {
        let associatedTypeUse = RuntimeAssociatedTypeUse(
            names: ["Element", "Failure", "Element"]
        )
        let method = method(
            slot: 0,
            name: "result()",
            resultAssociatedTypeUse: associatedTypeUse
        )

        #expect(associatedTypeUse.names == ["Element", "Failure"])
        #expect(associatedTypeUse.isDependent)
        #expect(method.returnAssociatedTypeUse == associatedTypeUse)
        #expect(
            method.signatureDescription
                == "method () -> Swift.String [associated Element, Failure]"
        )
    }

    private func method(
        slot: Int,
        name: String,
        kind: RuntimeRequirementKind = .method,
        resultConvention: RuntimeValueConvention = .concrete,
        resultAssociatedTypeUse: RuntimeAssociatedTypeUse = .none
    ) -> RuntimeMethod {
        RuntimeMethod(
            kind: kind,
            receiver: .instance,
            origin: .automatic,
            name: name,
            slot: slot,
            witnessSlot: slot,
            arguments: [],
            result: RuntimeValue(
                type: String.self,
                convention: resultConvention,
                associatedTypeUse: resultAssociatedTypeUse
            ),
            typedErrorType: nil,
            typedErrorAssociatedTypeUse: nil,
            selfIsClassConstrained: false,
            isThrowing: false,
            isAsync: false,
            hasReliableThrowing: true
        )
    }
}

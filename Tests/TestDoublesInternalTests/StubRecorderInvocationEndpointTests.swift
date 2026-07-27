import InternalRuntimeContract
import Testing
@testable import TestDoubles

@Suite struct StubRecorderInvocationEndpointTests {
    @Test func semanticMethodProjectionDrivesForwardingAndCapture() {
        let recorder = StubRecorder(
            methods: [method(slot: 0, name: "load()")],
            allowsForwardingFallback: true
        )
        let endpoint = StubRecorderInvocationEndpoint(recorder: recorder)

        #expect(endpoint.invocationMode == .normal)
        _ = recorder.captureCalls {
            #expect(endpoint.invocationMode == .capturing)
            if case .recording = endpoint.prepareDispatch(
                RuntimeInvocationRequest(slot: 0, arguments: [])
            ) {
                #expect(Bool(true))
            } else {
                #expect(Bool(false))
            }
            if case .recording = endpoint.prepareAsyncDispatch(
                RuntimeInvocationRequest(slot: 0, arguments: [])
            ) {
                #expect(Bool(true))
            } else {
                #expect(Bool(false))
            }
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
        let optionalSelf = method(
            slot: 2,
            name: "optionalCopy()",
            kind: .getter,
            resultConvention: .optionalSelf
        )
        let initializer = method(
            slot: 3,
            name: "init()",
            kind: .initializer,
            resultConvention: .optionalSelf
        )
        let recorder = StubRecorder(
            methods: [getter, setter, optionalSelf, initializer],
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
        expectPayload(
            endpoint.dependentResult(
                for: SelfResultDispatchOutcome.success,
                at: 0
            ))
        expectPayload(
            endpoint.dependentResult(
                for: OptionalSelfResultDispatchOutcome.value,
                at: 2
            ))
        expectNilPayload(
            endpoint.dependentResult(
                for: OptionalSelfResultDispatchOutcome.nilValue,
                at: 2
            ))
        expectPayload(
            endpoint.dependentResult(
                for: InitializerDispatchOutcome.success,
                at: 3
            ))
        expectNilPayload(
            endpoint.dependentResult(
                for: InitializerDispatchOutcome.failure,
                at: 3
            ))
    }

    private func method(
        slot: Int,
        name: String,
        kind: RuntimeRequirementKind = .method,
        resultConvention: RuntimeValueConvention = .concrete
    ) -> RuntimeMethod {
        RuntimeMethod(
            kind: kind,
            receiver: .instance,
            origin: .automatic,
            name: name,
            slot: slot,
            arguments: [],
            result: RuntimeValue(
                type: String.self,
                convention: resultConvention,
                associatedTypeUse: .none
            ),
            typedErrorType: nil,
            typedErrorAssociatedTypeUse: nil,
            selfIsClassConstrained: false,
            isThrowing: false,
            isAsync: false,
            hasReliableThrowing: true
        )
    }

    private func expectPayload(_ result: RuntimeDependentResult) {
        if case .payload = result {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }

    private func expectNilPayload(_ result: RuntimeDependentResult) {
        if case .nilPayload = result {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }
}

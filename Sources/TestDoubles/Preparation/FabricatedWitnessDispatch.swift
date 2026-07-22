import Echo

struct ReadWitnessPlan {
    let method: MethodDescriptor
    let resumeDiscriminator: UInt16
}

enum FabricatedWitnessDispatch {
    case stub(
        recorder: StubRecorder,
        methodsByIndex: [Int: MethodDescriptor],
        forwarder: (any ProtocolForwarding)?
    )
    case dummy(DummyInvocation)

    var invocationTarget: FabricatedInvocationTarget {
        switch self {
            case .stub(let recorder, _, let forwarder):
                if let forwarder {
                    return .spy(recorder, forwarder)
                }
                return .stub(recorder)
            case .dummy(let invocation):
                return .dummy(invocation)
        }
    }

    func attachRuntimeResources(_ resources: StubResources) {
        guard case .stub(let recorder, _, _) = self else { return }
        recorder.attachRuntimeResources(resources)
    }

    func makeCallableTrampoline(
        for requirement: ProtocolLayout.CallableRequirement,
        in node: ProtocolLayout.Node,
        witnessTable: UnsafeMutableRawPointer,
        resources: StubResources
    ) throws -> UnsafeRawPointer {
        let trampoline: UnsafeRawPointer?
        switch self {
            case .stub(let recorder, let methodsByIndex, _):
                guard let method = methodsByIndex[requirement.dispatchIndex] else {
                    throw StubError.requirementCountMismatch(
                        protocolName: node.descriptor.name,
                        expected: node.callableRequirements.count,
                        actual: 0
                    )
                }
                trampoline =
                    if let factory = method.typedWitnessAdapterFactory {
                        resources.makeTypedTrampoline(
                            factory: factory,
                            recorder: recorder,
                            method: method
                        )
                    } else {
                        resources.makeTrampoline(
                            kind: method.isAsync ? .asynchronous : .synchronous,
                            slot: method.index,
                            context: UnsafeRawPointer(witnessTable)
                        )
                    }

            case .dummy:
                let flags = requirement.protocolDescriptor
                    .requirements[requirement.witnessIndex].flags
                trampoline = resources.makeTrampoline(
                    kind: flags.isAsync ? .asynchronous : .synchronous,
                    slot: requirement.dispatchIndex,
                    context: UnsafeRawPointer(witnessTable)
                )
        }

        guard let trampoline else {
            throw StubError.trampolineAllocationFailed(
                requirementIndex: requirement.dispatchIndex
            )
        }
        return trampoline
    }

    func readPlan(
        for requirement: ProtocolLayout.ReadCoroutineRequirement,
        in node: ProtocolLayout.Node
    ) throws -> ReadWitnessPlan {
        precondition(requirement.abi == .yieldOnce2)
        switch self {
            case .stub(_, let methodsByIndex, _):
                guard let method = methodsByIndex[requirement.recorderDispatchIndex]
                else {
                    throw StubError.requirementCountMismatch(
                        protocolName: node.descriptor.name,
                        expected: node.callableRequirements.count,
                        actual: 0
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
                    let resumeDiscriminator =
                        ReadCoroutineRuntime.resumeDiscriminator(for: method)
                else {
                    throw StubError.unsupportedProtocolShape(
                        protocolName: node.descriptor.name,
                        reason:
                            "The read requirement at witness index \(requirement.witnessIndex) is outside the supported synchronous, nonthrowing borrowed-value ABI. "
                            + "Function, dynamic Self, typed-adapter, and result layouts whose resume discriminator cannot be derived require a hand-written test double."
                    )
                }
                return ReadWitnessPlan(
                    method: method,
                    resumeDiscriminator: resumeDiscriminator
                )

            case .dummy:
                throw StubError.unsupportedProtocolShape(
                    protocolName: node.descriptor.name,
                    reason: "Dummy cannot fabricate the result-dependent resume ABI for the read requirement at witness index \(requirement.witnessIndex). Use a Stub or a hand-written dummy."
                )
        }
    }
}

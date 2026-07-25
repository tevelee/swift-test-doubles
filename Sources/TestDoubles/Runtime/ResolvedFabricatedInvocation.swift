struct ResolvedFabricatedInvocation {
    let slot: Int
    let target: FabricatedInvocationTarget
    let recorder: StubRecorder
    let endpoint: StubRecorderInvocationEndpoint
    let runtimeMethod: PreparedRuntimeMethod?

    var forwarder: (any RuntimeForwarding)? { target.forwarder }

    static func resolve(
        in frame: TrampolineCallFrame
    ) -> ResolvedFabricatedInvocation? {
        guard let key = UnsafeRawPointer(bitPattern: frame.context),
            let target = FabricatedInvocationRegistry.resolveOptional(key)
        else {
            return nil
        }
        return ResolvedFabricatedInvocation(
            slot: frame.slot,
            target: target,
            recorder: target.recorderOrReject(slot: frame.slot),
            endpoint: {
                guard case .stub(let invocation) = target else {
                    preconditionFailure("[TestDoubles] Dummy invocation did not reject.")
                }
                return invocation.endpoint
            }(),
            runtimeMethod: target.method(at: frame.slot)
        )
    }

    func requireRuntimeMethod(
        failureMessage: @autoclosure () -> String
    ) -> PreparedRuntimeMethod {
        guard let runtimeMethod else {
            fatalError(failureMessage())
        }
        return runtimeMethod
    }

    func requireMethod(
        failureMessage: @autoclosure () -> String
    ) -> MethodDescriptor {
        requireRuntimeMethod(failureMessage: failureMessage()).descriptor
    }
}
import TestDoublesRuntime

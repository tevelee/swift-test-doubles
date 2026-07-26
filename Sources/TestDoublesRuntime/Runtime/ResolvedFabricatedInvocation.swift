import InternalRuntimeContract
import TestDoublesRuntimeMetadata

struct ResolvedFabricatedInvocation {
    let slot: Int
    let invocation: RuntimeFabricatedInvocation
    let runtimeMethod: PreparedRuntimeMethod?

    var endpoint: any RuntimeInvocationEndpoint { invocation.endpoint }
    var forwarder: (any RuntimeForwarding)? { invocation.forwarder }

    static func resolve(
        in frame: TrampolineCallFrame
    ) -> ResolvedFabricatedInvocation? {
        guard let key = UnsafeRawPointer(bitPattern: frame.context),
            let invocation = FabricatedInvocationRegistry.resolveOptional(key)
        else {
            return nil
        }
        return ResolvedFabricatedInvocation(
            slot: frame.slot,
            invocation: invocation,
            runtimeMethod: invocation.method(at: frame.slot)
        )
    }

    func requireRuntimeMethod(
        failureMessage: @autoclosure () -> String
    ) -> PreparedRuntimeMethod {
        guard let runtimeMethod else {
            endpoint.rejectInvocation(at: slot)
        }
        return runtimeMethod
    }

    func requireMethod(
        failureMessage: @autoclosure () -> String
    ) -> MethodDescriptor {
        requireRuntimeMethod(failureMessage: failureMessage()).descriptor
    }
}

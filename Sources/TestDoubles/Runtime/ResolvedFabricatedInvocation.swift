struct ResolvedFabricatedInvocation {
    let slot: Int
    let target: FabricatedInvocationTarget
    let recorder: StubRecorder

    var forwarder: (any ProtocolForwarding)? { target.forwarder }

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
            recorder: target.recorderOrReject(slot: frame.slot)
        )
    }

    func requireMethod(
        failureMessage: @autoclosure () -> String
    ) -> MethodDescriptor {
        guard let method = recorder.runtimeMethod(for: slot) else {
            fatalError(failureMessage())
        }
        return method
    }
}

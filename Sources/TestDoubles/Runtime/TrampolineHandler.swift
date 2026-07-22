import CTestDoublesTrampoline

@_cdecl("td_swift_trampoline_handler")
func td_swift_trampoline_handler(_ rawFrame: UnsafeMutablePointer<TDCallFrame>?) {
    guard let rawFrame else { return }
    RuntimeTrampolineHandler.handle(TrampolineCallFrame(rawFrame))
}

@_cdecl("td_swift_async_trampoline_handler")
func td_swift_async_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) -> TDAsyncTrampolineResult {
    guard let rawFrame else {
        return TDAsyncTrampolineResult(state: nil, stackAdjustment: 0)
    }
    return RuntimeTrampolineHandler.prepareAsync(
        TrampolineCallFrame(rawFrame)
    )
}

@_silgen_name("td_swift_async_dispatch")
func td_swift_async_dispatch(_ rawState: UnsafeMutableRawPointer) async {
    await RuntimeTrampolineHandler.dispatchAsync(rawState)
}

@_cdecl("td_swift_async_dispatch_finish")
func td_swift_async_dispatch_finish(
    _ rawState: UnsafeMutableRawPointer?,
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) {
    guard let rawState, let rawFrame else { return }
    RuntimeTrampolineHandler.finishAsync(
        rawState,
        into: TrampolineCallFrame(rawFrame)
    )
}

protocol AsyncTrampolineDispatchState: AnyObject, Sendable {
    func run() async
    func finish(into frame: TrampolineCallFrame)
}

enum RuntimeTrampolineHandler {
    private struct Invocation {
        let target: FabricatedInvocationTarget
        let recorder: StubRecorder
        let method: MethodDescriptor
        let decodedArguments: DecodedArguments

        var forwarder: (any ProtocolForwarding)? { target.forwarder }
    }

    /// Retained by the assembly bridge while the handler is suspended. A state
    /// belongs to one invocation: the caller task mutates it, then the completion
    /// functlet consumes the retain only after `dispatchAsync` has returned.
    private final class AsyncDispatchState:
        AsyncTrampolineDispatchState,
        @unchecked Sendable
    {
        var frame: TDCallFrame
        let method: MethodDescriptor
        let recorder: StubRecorder
        let args: [Any]
        let typedErrorDestination: UnsafeMutableRawPointer?
        let handler: ([Any]) async throws -> Any

        init(
            frame: TDCallFrame,
            method: MethodDescriptor,
            recorder: StubRecorder,
            decodedArguments: DecodedArguments,
            handler: @escaping ([Any]) async throws -> Any
        ) {
            self.frame = frame
            self.method = method
            self.recorder = recorder
            self.args = decodedArguments.values
            self.typedErrorDestination =
                decodedArguments.typedErrorDestination
            self.handler = handler
        }

        func run() async {
            do {
                let result = try await handler(args)
                withUnsafeMutablePointer(to: &frame) { pointer in
                    let frame = TrampolineCallFrame(pointer)
                    frame.storeReturnError(0)
                    RuntimeResultEncoder.encodeDispatchResult(
                        result,
                        for: method,
                        recorder: recorder,
                        into: frame
                    )
                }
            } catch {
                withUnsafeMutablePointer(to: &frame) { pointer in
                    RuntimeTrampolineHandler.encodeThrown(
                        error,
                        from: method,
                        typedErrorDestination: typedErrorDestination,
                        into: TrampolineCallFrame(pointer)
                    )
                }
            }
        }

        func finish(into frame: TrampolineCallFrame) {
            frame.restore(self.frame)
        }
    }

    static func handle(_ frame: TrampolineCallFrame) {
        let invocation = invocation(for: frame)
        handle(
            frame,
            forwarder: invocation.forwarder,
            recorder: invocation.recorder,
            method: invocation.method,
            decodedArguments: invocation.decodedArguments
        )
    }

    private static func handle(
        _ frame: TrampolineCallFrame,
        forwarder: (any ProtocolForwarding)?,
        recorder: StubRecorder,
        method: MethodDescriptor,
        decodedArguments: DecodedArguments
    ) {
        let result: Any
        switch recorder.prepareDispatch(
            method: method,
            args: decodedArguments.values
        ) {
            case .placeholder:
                if method.isThrowing || method.isAsync {
                    frame.storeReturnError(0)
                } else {
                    frame.storeReturnError(frame.incomingSwiftError)
                }
                RuntimeResultEncoder.encodeRecordingResult(
                    for: method,
                    args: decodedArguments.values,
                    recorder: recorder,
                    into: frame
                )
                return

            case .forwarding:
                guard let forwarder else {
                    preconditionFailure(
                        "[TestDoubles] A forwarding dispatch has no Spy target."
                    )
                }
                forwarder.forward(method, frame: frame)
                return

            case .behavior(let behavior):
                if forwarder != nil {
                    _ = RuntimeArgumentDecoder.decode(
                        for: method,
                        from: frame,
                        consumeOwnedArguments: true
                    )
                }
                do {
                    switch behavior {
                        case .fixed(let fixedResult):
                            result = try fixedResult.get()
                        case .fixedSequence:
                            preconditionFailure(
                                "[TestDoubles] A queued stub result was not reserved during dispatch."
                            )
                        case .immediate(let handler):
                            result = try handler(decodedArguments.values)
                        case .suspending:
                            fatalError(
                                "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(method.name). "
                                    + "Use it only with an async Stub requirement."
                            )
                    }
                    if method.isThrowing || method.isAsync {
                        frame.storeReturnError(0)
                    } else {
                        frame.storeReturnError(frame.incomingSwiftError)
                    }
                } catch {
                    encodeThrown(
                        error,
                        from: method,
                        typedErrorDestination: decodedArguments.typedErrorDestination,
                        into: frame
                    )
                    return
                }
        }

        RuntimeResultEncoder.encodeDispatchResult(
            result,
            for: method,
            recorder: recorder,
            into: frame
        )
    }

    static func prepareAsync(
        _ frame: TrampolineCallFrame
    ) -> TDAsyncTrampolineResult {
        if frame.slot == Int.max {
            return prepareDynamicAsyncFunctionReturn(frame)
        }
        let invocation = invocation(for: frame)
        let state = prepareAsync(frame, invocation: invocation)
        let stackAdjustment = asyncWitnessStackPlan(
            for: invocation.method,
            architecture: .current
        ).stackAdjustmentByteCount
        return TDAsyncTrampolineResult(
            state: state,
            stackAdjustment: UInt64(stackAdjustment)
        )
    }

    private static func prepareAsync(
        _ frame: TrampolineCallFrame,
        invocation: Invocation
    ) -> UnsafeMutableRawPointer? {
        switch invocation.recorder.prepareAsyncDispatch(
            method: invocation.method,
            args: invocation.decodedArguments.values
        ) {
            case .placeholder:
                frame.storeReturnError(0)
                RuntimeResultEncoder.encodeRecordingResult(
                    for: invocation.method,
                    args: invocation.decodedArguments.values,
                    recorder: invocation.recorder,
                    into: frame
                )
                return nil

            case .immediate(.success(let result)):
                consumeOwnedArgumentsForOverride(invocation, from: frame)
                frame.storeReturnError(0)
                RuntimeResultEncoder.encodeDispatchResult(
                    result,
                    for: invocation.method,
                    recorder: invocation.recorder,
                    into: frame
                )
                return nil

            case .immediate(.failure(let error)):
                consumeOwnedArgumentsForOverride(invocation, from: frame)
                encodeThrown(
                    error,
                    from: invocation.method,
                    typedErrorDestination: invocation.decodedArguments
                        .typedErrorDestination,
                    into: frame
                )
                return nil

            case .suspending(let handler):
                consumeOwnedArgumentsForOverride(invocation, from: frame)
                let state = AsyncDispatchState(
                    frame: frame.snapshot,
                    method: invocation.method,
                    recorder: invocation.recorder,
                    decodedArguments: invocation.decodedArguments,
                    handler: handler
                )
                return Unmanaged.passRetained(state).toOpaque()

            case .forwarding:
                guard let forwarder = invocation.forwarder else {
                    preconditionFailure(
                        "[TestDoubles] A forwarding async dispatch has no Spy target."
                    )
                }
                let state = forwarder.makeAsyncState(
                    for: invocation.method,
                    frame: frame
                )
                return Unmanaged.passRetained(state as AnyObject).toOpaque()
        }
    }

    static func dispatchAsync(_ rawState: UnsafeMutableRawPointer) async {
        let object = Unmanaged<AnyObject>.fromOpaque(rawState)
            .takeUnretainedValue()
        guard let state = object as? any AsyncTrampolineDispatchState else {
            preconditionFailure(
                "[TestDoubles] Async trampoline state has an invalid type."
            )
        }
        await state.run()
    }

    static func finishAsync(
        _ rawState: UnsafeMutableRawPointer,
        into frame: TrampolineCallFrame
    ) {
        let object = Unmanaged<AnyObject>.fromOpaque(rawState)
            .takeRetainedValue()
        guard let state = object as? any AsyncTrampolineDispatchState else {
            preconditionFailure(
                "[TestDoubles] Async trampoline state has an invalid type."
            )
        }
        state.finish(into: frame)
    }

    /// Encodes a handler's thrown error into the call frame, trapping when
    /// the requirement's witness convention has no error channel.
    private static func encodeThrown(
        _ error: any Error,
        from method: MethodDescriptor,
        typedErrorDestination: UnsafeMutableRawPointer?,
        into frame: TrampolineCallFrame
    ) {
        guard method.isThrowing else {
            fatalError(
                "[TestDoubles] A nonthrowing \(method.isAsync ? "async " : "")stub handler threw \(error)."
            )
        }
        RuntimeResultEncoder.encodeFailure(
            error,
            for: method,
            typedErrorDestination: typedErrorDestination,
            into: frame
        )
    }

    static func findRecorder(in frame: TrampolineCallFrame) -> StubRecorder? {
        guard let key = UnsafeRawPointer(bitPattern: frame.context),
            let target = FabricatedInvocationRegistry.resolveOptional(key)
        else {
            return nil
        }
        return target.recorderOrReject(slot: frame.slot)
    }

    private static func invocation(for frame: TrampolineCallFrame) -> Invocation {
        let slot = frame.slot
        guard let key = UnsafeRawPointer(bitPattern: frame.context),
            let target = FabricatedInvocationRegistry.resolveOptional(key)
        else {
            fatalError(
                "[TestDoubles] Trampoline could not resolve recorder for witness call at slot \(slot)."
            )
        }
        let recorder = target.recorderOrReject(slot: slot)
        guard let method = recorder.runtimeMethod(for: slot) else {
            fatalError(
                "[TestDoubles] No method descriptor registered for witness slot \(slot)."
            )
        }
        return Invocation(
            target: target,
            recorder: recorder,
            method: method,
            decodedArguments: RuntimeArgumentDecoder.decode(
                for: method,
                from: frame,
                consumeOwnedArguments:
                    target.forwarder == nil || recorder.mode == .capturing
            )
        )
    }

    private static func consumeOwnedArgumentsForOverride(
        _ invocation: Invocation,
        from frame: TrampolineCallFrame
    ) {
        guard invocation.forwarder != nil else { return }
        _ = RuntimeArgumentDecoder.decode(
            for: invocation.method,
            from: frame,
            consumeOwnedArguments: true
        )
    }
}

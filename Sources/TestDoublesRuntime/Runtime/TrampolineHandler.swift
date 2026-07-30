import CTestDoublesTrampoline
import InternalRuntimeContract
import TestDoublesRuntimeMetadata

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
    return RuntimeTrampolineHandler.prepareAsync(TrampolineCallFrame(rawFrame))
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
    RuntimeTrampolineHandler.finishAsync(rawState, into: TrampolineCallFrame(rawFrame))
}

enum RuntimeTrampolineHandler {
    private struct Invocation {
        let endpoint: any RuntimeInvocationEndpoint
        let forwarder: (any RuntimeForwarding)?
        let runtimeMethod: PreparedRuntimeMethod
        let decodedArguments: DecodedArguments

        var method: MethodDescriptor { runtimeMethod.descriptor }
    }

    /// Retained by the assembly bridge while the handler is suspended. A state
    /// belongs to one invocation: the caller task mutates it, then the completion
    /// functlet consumes the retain only after `dispatchAsync` has returned.
    private final class AsyncDispatchState:
        AsyncTrampolineDispatchState,
        @unchecked Sendable
    {
        var frame: TDCallFrame
        let runtimeMethod: PreparedRuntimeMethod
        let endpoint: any RuntimeInvocationEndpoint
        let args: [Any]
        let genericParameterTypes: [Any.Type]
        let typedErrorDestination: UnsafeMutableRawPointer?
        let handler: ([Any]) async throws -> Any

        init(
            frame: TDCallFrame,
            runtimeMethod: PreparedRuntimeMethod,
            endpoint: any RuntimeInvocationEndpoint,
            decodedArguments: DecodedArguments,
            handler: @escaping ([Any]) async throws -> Any
        ) {
            self.frame = frame
            self.runtimeMethod = runtimeMethod
            self.endpoint = endpoint
            args = decodedArguments.values
            genericParameterTypes = decodedArguments.genericParameterTypes
            typedErrorDestination = decodedArguments.typedErrorDestination
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
                        for: runtimeMethod,
                        endpoint: endpoint,
                        genericParameterTypes: genericParameterTypes,
                        into: frame
                    )
                }
            } catch {
                withUnsafeMutablePointer(to: &frame) { pointer in
                    RuntimeTrampolineHandler.encodeThrown(
                        error,
                        from: runtimeMethod.descriptor,
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

    private final class ForwardingCompletionState:
        AsyncTrampolineDispatchState,
        @unchecked Sendable
    {
        let base: any AsyncTrampolineDispatchState
        let endpoint: any RuntimeInvocationEndpoint
        let token: RuntimeInvocationToken

        init(
            base: any AsyncTrampolineDispatchState,
            endpoint: any RuntimeInvocationEndpoint,
            token: RuntimeInvocationToken
        ) {
            self.base = base
            self.endpoint = endpoint
            self.token = token
        }

        func run() async {
            await base.run()
            endpoint.completeForwardedInvocation(token)
        }

        func finish(into frame: TrampolineCallFrame) {
            base.finish(into: frame)
        }
    }

    static func handle(_ frame: TrampolineCallFrame) {
        let invocation = invocation(for: frame)
        handle(frame, invocation: invocation)
    }

    private static func handle(
        _ frame: TrampolineCallFrame,
        invocation: Invocation
    ) {
        let method = invocation.method
        let result: Any
        let completionToken: RuntimeInvocationToken
        switch invocation.endpoint.prepareDispatch(
            RuntimeInvocationRequest(
                slot: method.index,
                arguments: invocation.decodedArguments.values
            )
        ) {
            case .recording:
                if method.isThrowing || method.isAsync {
                    frame.storeReturnError(0)
                } else {
                    frame.storeReturnError(frame.incomingSwiftError)
                }
                RuntimeResultEncoder.encodeRecordingResult(
                    for: method,
                    args: invocation.decodedArguments.values,
                    endpoint: invocation.endpoint,
                    genericParameterTypes:
                        invocation.decodedArguments.genericParameterTypes,
                    into: frame
                )
                return

            case .forwarding(let token):
                guard let forwarder = invocation.forwarder else {
                    preconditionFailure(
                        "[TestDoubles] A forwarding dispatch has no target transport."
                    )
                }
                forwarder.forward(method, frame: frame)
                invocation.endpoint.completeForwardedInvocation(token)
                return

            case .behavior(let token, let behavior):
                completionToken = token
                if invocation.forwarder != nil {
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
                        case .immediate(let handler):
                            result = try handler(invocation.decodedArguments.values)
                        case .suspending:
                            fatalError(
                                "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(method.name). Use it only with an async requirement."
                            )
                    }
                    if method.isThrowing || method.isAsync {
                        frame.storeReturnError(0)
                    } else {
                        frame.storeReturnError(frame.incomingSwiftError)
                    }
                } catch {
                    invocation.endpoint.completeInvocation(
                        token,
                        outcome: .threw(error)
                    )
                    encodeThrown(
                        error,
                        from: method,
                        typedErrorDestination: invocation.decodedArguments
                            .typedErrorDestination,
                        into: frame
                    )
                    return
                }
        }

        RuntimeResultEncoder.encodeDispatchResult(
            result,
            for: invocation.runtimeMethod,
            endpoint: invocation.endpoint,
            genericParameterTypes:
                invocation.decodedArguments.genericParameterTypes,
            into: frame
        )
        invocation.endpoint.completeInvocation(
            completionToken,
            outcome: .returned(result)
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
        guard let stackAdjustment = invocation.runtimeMethod.asyncStackAdjustmentByteCount else {
            preconditionFailure(
                "[TestDoubles] Async trampoline method has no stack adjustment plan."
            )
        }
        return TDAsyncTrampolineResult(
            state: state,
            stackAdjustment: UInt64(stackAdjustment)
        )
    }

    private static func prepareAsync(
        _ frame: TrampolineCallFrame,
        invocation: Invocation
    ) -> UnsafeMutableRawPointer? {
        switch invocation.endpoint.prepareAsyncDispatch(
            RuntimeInvocationRequest(
                slot: invocation.method.index,
                arguments: invocation.decodedArguments.values
            )
        ) {
            case .recording:
                frame.storeReturnError(0)
                RuntimeResultEncoder.encodeRecordingResult(
                    for: invocation.method,
                    args: invocation.decodedArguments.values,
                    endpoint: invocation.endpoint,
                    genericParameterTypes:
                        invocation.decodedArguments.genericParameterTypes,
                    into: frame
                )
                return nil

            case .immediate(.success(let result)):
                consumeOwnedArgumentsForOverride(invocation, from: frame)
                frame.storeReturnError(0)
                RuntimeResultEncoder.encodeDispatchResult(
                    result,
                    for: invocation.runtimeMethod,
                    endpoint: invocation.endpoint,
                    genericParameterTypes:
                        invocation.decodedArguments.genericParameterTypes,
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
                    runtimeMethod: invocation.runtimeMethod,
                    endpoint: invocation.endpoint,
                    decodedArguments: invocation.decodedArguments,
                    handler: handler
                )
                return RetainedRuntimeState.retain(state)

            case .forwarding(let token):
                guard let forwarder = invocation.forwarder else {
                    preconditionFailure(
                        "[TestDoubles] A forwarding async dispatch has no target transport."
                    )
                }
                let state = ForwardingCompletionState(
                    base: forwarder.makeAsyncState(
                        for: invocation.method,
                        frame: frame
                    ),
                    endpoint: invocation.endpoint,
                    token: token
                )
                return RetainedRuntimeState.retain(state)
        }
    }

    static func dispatchAsync(_ rawState: UnsafeMutableRawPointer) async {
        let state = RetainedRuntimeState.borrow(
            (any AsyncTrampolineDispatchState).self,
            from: rawState,
            invalidTypeMessage:
                "[TestDoubles] Async trampoline state has an invalid type."
        )
        await state.run()
    }

    static func finishAsync(
        _ rawState: UnsafeMutableRawPointer,
        into frame: TrampolineCallFrame
    ) {
        let state = RetainedRuntimeState.consume(
            (any AsyncTrampolineDispatchState).self,
            from: rawState,
            invalidTypeMessage:
                "[TestDoubles] Async trampoline state has an invalid type."
        )
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
                "[TestDoubles] A nonthrowing \(method.isAsync ? "async " : "")handler threw \(error)."
            )
        }
        RuntimeResultEncoder.encodeFailure(
            error,
            for: method,
            typedErrorDestination: typedErrorDestination,
            into: frame
        )
    }

    private static func invocation(for frame: TrampolineCallFrame) -> Invocation {
        let slot = frame.slot
        guard let resolved = ResolvedFabricatedInvocation.resolve(in: frame) else {
            fatalError(
                "[TestDoubles] Trampoline could not resolve runtime endpoint for witness call at slot \(slot)."
            )
        }
        let runtimeMethod = resolved.requireRuntimeMethod(
            failureMessage:
                "[TestDoubles] No method descriptor registered for witness slot \(slot)."
        )
        return Invocation(
            endpoint: resolved.endpoint,
            forwarder: resolved.forwarder,
            runtimeMethod: runtimeMethod,
            decodedArguments: RuntimeArgumentDecoder.decode(
                for: runtimeMethod,
                from: frame,
                consumeOwnedArguments:
                    resolved.forwarder == nil
                    || resolved.endpoint.invocationMode == .capturing
            )
        )
    }

    private static func consumeOwnedArgumentsForOverride(
        _ invocation: Invocation,
        from frame: TrampolineCallFrame
    ) {
        guard invocation.forwarder != nil else { return }
        _ = RuntimeArgumentDecoder.decode(
            for: invocation.runtimeMethod,
            from: frame,
            consumeOwnedArguments: true
        )
    }
}

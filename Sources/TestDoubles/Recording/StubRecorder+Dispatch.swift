import Foundation

extension StubRecorder {
    func dispatch(method: MethodDescriptor, args: [Any]) throws -> Any {
        switch prepareDispatch(method: method, args: args) {
            case .placeholder:
                return zeroValue

            case .behavior(let behavior):
                switch behavior {
                    case .fixed(let result):
                        return try result.get()
                    case .fixedSequence:
                        preconditionFailure(
                            "[TestDoubles] A queued stub result was not reserved during dispatch."
                        )
                    case .immediate(let handler):
                        return try handler(args)
                    case .suspending:
                        fatalError(
                            "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(method.name). "
                                + "Use it only with an async Stub requirement."
                        )
                }

            case .forwarding:
                preconditionFailure(
                    "[TestDoubles] A forwarding dispatch requires a Spy runtime target."
                )
        }
    }

    func dispatchTyped<Result>(
        method: MethodDescriptor,
        args: [Any],
        as type: Result.Type
    ) throws -> Result {
        if mode == .capturing {
            _ = try? dispatch(method: method, args: args)
            return RecordingReturnPlaceholderContext.requiredValue(
                for: type,
                method: method.name
            )
        }
        return requireStubbedResult(
            try dispatch(method: method, args: args),
            as: type,
            method: method.name
        )
    }

    /// Selects and records a suspending handler without invoking it under the
    /// recorder lock. Recording and verification continue through the immediate
    /// dispatch path so their placeholder-return behavior remains synchronous.
    func prepareAsyncDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> AsyncDispatch {
        switch prepareDispatch(method: method, args: args) {
            case .placeholder:
                return .placeholder

            case .behavior(let behavior):
                switch behavior {
                    case .fixed(let result):
                        return .immediate(result)
                    case .fixedSequence:
                        preconditionFailure(
                            "[TestDoubles] A queued stub result was not reserved during dispatch."
                        )
                    case .immediate(let handler):
                        do {
                            return .immediate(.success(try handler(args)))
                        } catch {
                            return .immediate(.failure(error))
                        }
                    case .suspending(let handler):
                        return .suspending(handler)
                }

            case .forwarding:
                return .forwarding
        }
    }

    func prepareDispatch(
        method: MethodDescriptor,
        args: [Any]
    ) -> PreparedDispatch {
        let methodIndex = method.index
        if StubCaptureCoordinator.isCapturing(self) {
            recordPlaceholder(method: methodIndex, name: method.name, args: args)
            return .placeholder
        }

        while true {
            let snapshot = withLockedPolicy {
                $0.behaviorRegistry.snapshot(for: methodIndex)
            }
            guard let entries = snapshot.entries else {
                guard behaviorRegistryIsCurrent(snapshot) else { continue }
                if allowsForwardingFallback {
                    recordForwardedInvocation(method: method, args: args)
                    return .forwarding
                }
                fatalError(
                    diagnosticMessage(
                        title: "No stub configured",
                        method: method,
                        args: args,
                        entries: []
                    ))
            }
            guard
                let preparedMatch = StubBehaviorRegistry.firstPreparedEntryMatch(
                    for: args,
                    in: entries
                )
            else {
                guard behaviorRegistryIsCurrent(snapshot) else { continue }
                if allowsForwardingFallback {
                    recordForwardedInvocation(method: method, args: args)
                    return .forwarding
                }
                fatalError(
                    diagnosticMessage(
                        title: "No matching stub",
                        method: method,
                        args: args,
                        entries: entries
                    ))
            }
            let entry = entries[preparedMatch.entryIndex]

            let committed: (PreparedDispatch, [InvocationLedgerWaiter])? =
                withLockedPolicy { policy in
                    guard policy.behaviorRegistry.isCurrent(snapshot) else { return nil }
                    policy.behaviorRegistry.markConsumed(
                        method: methodIndex,
                        entryIndex: preparedMatch.entryIndex
                    )
                    let dispatch = preparedBehavior(
                        entry.behavior,
                        method: method,
                        args: args,
                        entries: entries
                    )
                    let waiters = policy.invocationLedger.append(
                        method: methodIndex,
                        name: method.name,
                        args: args,
                        argumentConventions: recordingArgumentConventions(for: method),
                        runtimePayloadRecorder: self
                    )
                    preparedMatch.matcherTransaction.commitCaptures()
                    return (dispatch, waiters)
                }
            guard let (dispatch, waiters) = committed else { continue }
            resumeWaiters(waiters, returning: .changed)
            return dispatch
        }
    }

    private func behaviorRegistryIsCurrent(
        _ snapshot: StubBehaviorRegistry.Snapshot
    ) -> Bool {
        withLockedPolicy { $0.behaviorRegistry.isCurrent(snapshot) }
    }

    private func preparedBehavior(
        _ behavior: StubEntry.Behavior,
        method: MethodDescriptor,
        args: [Any],
        entries: [StubEntry]
    ) -> PreparedDispatch {
        guard case .fixedSequence(let results) = behavior else {
            return .behavior(behavior)
        }
        switch results.next() {
            case .value(let result):
                return .behavior(.fixed(result))
            case .delayed(let result, let delay):
                let cancellableDelay = method.isThrowing
                return .behavior(
                    .suspending { _ in
                        try await StubRecorder.deliverFixedResult(
                            result,
                            after: delay,
                            cancellableDelay: cancellableDelay
                        )
                    })
            case .never:
                return .behavior(
                    .suspending { _ in
                        await StubRecorder.parkForever()
                    })
            case .awaitCancellation(let outcome):
                let isThrowing = method.isThrowing
                return .behavior(
                    .suspending { _ in
                        await StubRecorder.waitUntilCancelled()
                        switch outcome {
                            case .some(let result):
                                return try result.get()
                            case .none where isThrowing:
                                throw CancellationError()
                            case .none:
                                // Registration permits a nil outcome on a
                                // nonthrowing requirement only for Void.
                                return ()
                        }
                    })
            case .forward:
                guard allowsForwardingFallback else {
                    fatalError(
                        "[TestDoubles] thenForward requires a Spy with a forwarding target."
                    )
                }
                return .forwarding
            case .fatal(let message):
                let diagnostic = diagnosticMessage(
                    title: message.map { "Explicit stub failure: \($0)" }
                        ?? "Explicit stub failure",
                    method: method,
                    args: args,
                    entries: entries
                )
                return .behavior(
                    .immediate { _ in
                        fatalError(diagnostic)
                    })
        }
    }

    /// Delivers a queued fixed result after its configured delay. A throwing
    /// requirement's delay is cancellable and surfaces the cancellation error;
    /// a non-throwing requirement has no error channel for cancellation, so
    /// its delay always runs to completion.
    private static func deliverFixedResult(
        _ result: Result<Any, any Error>,
        after delay: Duration,
        cancellableDelay: Bool
    ) async throws -> Any {
        if cancellableDelay {
            try await ContinuousClock().sleep(for: delay)
        } else {
            await Task { try? await ContinuousClock().sleep(for: delay) }.value
        }
        return try result.get()
    }

    /// Suspends the calling task and never resumes it, deliberately ignoring
    /// cancellation: a parked call models a dependency that has wedged, and
    /// completing on cancellation is a different behavior's contract.
    private static func parkForever() async -> Never {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
        fatalError("[TestDoubles] A permanently parked call resumed.")
    }

    /// Suspends until the calling task is cancelled, resuming immediately for
    /// a task that is already cancelled on entry. Never throws: the caller
    /// decides how cancellation completes the stubbed call.
    private static func waitUntilCancelled() async {
        let state = CancellationWaitState()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.register(continuation)
            }
        } onCancel: {
            state.markCancelled()
        }
    }

    /// One suspension point's cancellation handshake. `onCancel` can run
    /// before, during, or after continuation registration, and on a different
    /// thread, so both sides synchronize on the lock and whichever side
    /// arrives second performs the resume.
    private final class CancellationWaitState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var isCancelled = false

        func register(_ continuation: CheckedContinuation<Void, Never>) {
            lock.lock()
            if isCancelled {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func markCancelled() {
            lock.lock()
            isCancelled = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }
    }

    private func recordForwardedInvocation(
        method: MethodDescriptor,
        args: [Any]
    ) {
        let waiters = withLockedPolicy {
            $0.invocationLedger.append(
                method: method.index,
                name: method.name,
                args: args,
                argumentConventions: recordingArgumentConventions(for: method),
                runtimePayloadRecorder: self
            )
        }
        resumeWaiters(waiters, returning: .changed)
    }

    private func recordPlaceholder(method: Int, name: String, args: [Any]) {
        var matchers = MatcherContext.takeMatchers()
        if runtimeMethod(for: method)?.kind == .setter,
            args.count > 1,
            matchers.count == args.count,
            let valueMatcher = matchers.last
        {
            // Swift evaluates a subscript assignment's index expressions
            // before its new-value expression, while the setter witness ABI
            // passes [newValue, indices...]. Keep captured matchers aligned
            // with the decoded runtime argument order.
            matchers = [valueMatcher] + Array(matchers.dropLast())
        }
        StubCaptureCoordinator.append(
            RecordedCall(
                methodIndex: method,
                name: name,
                args: args,
                matchers: matchers
            ),
            to: self
        )
    }

    private func recordingArgumentConventions(
        for method: MethodDescriptor
    ) -> [WitnessValueConvention]? {
        method.argumentConventions.contains {
            $0 == .selfType || $0 == .optionalSelf
        } ? method.argumentConventions : nil
    }

    // Sentinel value for capture mode returns.
    private var zeroValue: Any { 0 as Int }
}

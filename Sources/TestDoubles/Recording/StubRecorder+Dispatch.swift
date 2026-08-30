import InternalRuntimeContract
import Foundation

extension RuntimeArgumentCalibration {
    fileprivate func matchesPlaceholderBytes(of argument: Any) -> Bool {
        func matches<Value>(_ value: Value) -> Bool {
            guard let expected = bytes(for: Value.self) else { return false }
            return withUnsafeBytes(of: value) { Array($0) } == expected
        }
        return _openExistential(argument, do: matches)
    }
}

extension StubRecorder {
    func dispatchTyped<Result>(
        manualMethod: ManualMethod,
        args: [Any],
        as type: Result.Type
    ) throws -> Result {
        try dispatchTyped(method: manualMethod.descriptor, args: args, as: type)
    }

    func prepareAsyncDispatch(
        manualMethod: ManualMethod,
        args: [Any]
    ) -> AsyncDispatch {
        prepareAsyncDispatch(method: manualMethod.descriptor, args: args)
    }

    func dispatch(
        method: RuntimeMethod,
        args: [Any],
        forwardingTo fallback: (() throws -> Any)? = nil
    ) throws -> Any {
        switch prepareDispatch(method: method, args: args) {
            case .placeholder:
                return zeroValue

            case .behavior(let token, let behavior):
                do {
                    let result: Any
                    switch behavior {
                        case .fixed(let fixedResult):
                            result = try fixedResult.get()
                        case .fixedSequence:
                            preconditionFailure(
                                "[TestDoubles] A queued stub result was not reserved during dispatch."
                            )
                        case .immediate(let handler):
                            result = try handler(args)
                        case .suspending:
                            fatalError(
                                "[TestDoubles] A suspending handler was selected for synchronous dispatch of \(method.name). "
                                    + "Use it only with an async Stub requirement."
                            )
                    }
                    completeInvocation(token, outcome: .returned(result))
                    return result
                } catch {
                    completeInvocation(token, outcome: .threw(error))
                    throw error
                }

            case .forwarding(let token):
                guard let fallback else {
                    preconditionFailure(
                        "[TestDoubles] A forwarding dispatch requires a Spy target."
                    )
                }
                defer {
                    completeInvocation(token, outcome: .forwarded)
                }
                return try fallback()
        }
    }

    func dispatchTyped<Result>(
        method: RuntimeMethod,
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

    func dispatchTyped<Result>(
        manualMethod: ManualMethod,
        args: [Any],
        as type: Result.Type,
        forwardingTo fallback: @escaping () throws -> Result
    ) throws -> Result {
        if mode == .capturing {
            _ = try? dispatch(method: manualMethod.descriptor, args: args)
            return RecordingReturnPlaceholderContext.requiredValue(
                for: type,
                method: manualMethod.name
            )
        }
        return requireStubbedResult(
            try dispatch(
                method: manualMethod.descriptor,
                args: args,
                forwardingTo: fallback
            ),
            as: type,
            method: manualMethod.name
        )
    }

    /// Selects and records a suspending handler without invoking it under the
    /// recorder lock. Recording and verification continue through the immediate
    /// dispatch path so their placeholder-return behavior remains synchronous.
    func prepareAsyncDispatch(
        method: RuntimeMethod,
        args: [Any]
    ) -> AsyncDispatch {
        switch prepareDispatch(method: method, args: args) {
            case .placeholder:
                return .placeholder

            case .behavior(let token, let behavior):
                switch behavior {
                    case .fixed(let result):
                        completeInvocation(token, outcome: recordedOutcome(for: result))
                        return .immediate(result)
                    case .fixedSequence:
                        preconditionFailure(
                            "[TestDoubles] A queued stub result was not reserved during dispatch."
                        )
                    case .immediate(let handler):
                        do {
                            let result = try handler(args)
                            completeInvocation(token, outcome: .returned(result))
                            return .immediate(.success(result))
                        } catch {
                            completeInvocation(token, outcome: .threw(error))
                            return .immediate(.failure(error))
                        }
                    case .suspending(let handler):
                        return .suspending { [weak self] arguments in
                            do {
                                let result = try await handler(arguments)
                                self?.completeInvocation(token, outcome: .returned(result))
                                return result
                            } catch {
                                self?.completeInvocation(token, outcome: .threw(error))
                                throw error
                            }
                        }
                }

            case .forwarding(let token):
                return .forwarding(token)
        }
    }

    func prepareDispatch(
        method: RuntimeMethod,
        args: [Any]
    ) -> PreparedDispatch {
        let methodIndex = method.index
        if StubCaptureCoordinator.isCapturing(self) {
            recordPlaceholder(method: methodIndex, name: method.name, args: args)
            return .placeholder
        }
        let startedAt = ContinuousClock.now
        let callStack = capturedCallStack()

        while true {
            let snapshot = withLockedPolicy {
                $0.behaviorRegistry.snapshot(for: methodIndex)
            }
            guard let entries = snapshot.entries else {
                guard behaviorRegistryIsCurrent(snapshot) else { continue }
                if allowsForwardingFallback {
                    return .forwarding(
                        recordForwardedInvocation(
                            method: method,
                            args: args,
                            callStack: callStack,
                            startedAt: startedAt
                        )
                    )
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
                    in: entries,
                    candidateEntryIndices: snapshot.candidateEntryIndices(
                        for: args
                    )
                )
            else {
                guard behaviorRegistryIsCurrent(snapshot) else { continue }
                if allowsForwardingFallback {
                    return .forwarding(
                        recordForwardedInvocation(
                            method: method,
                            args: args,
                            callStack: callStack,
                            startedAt: startedAt
                        )
                    )
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

            let committed:
                (
                    PreparedDispatch,
                    [InvocationLedgerWaiter],
                    [StubBehaviorRegistry.SideEffect]
                )? =
                    withLockedPolicy { policy in
                        guard policy.behaviorRegistry.isCurrent(snapshot) else { return nil }
                        policy.behaviorRegistry.markConsumed(
                            method: methodIndex,
                            entryIndex: preparedMatch.entryIndex
                        )
                        let selectedDispatch = preparedBehavior(
                            entry.behavior,
                            method: method,
                            args: args,
                            entries: entries
                        )
                        let origin: InvocationOrigin =
                            if case .forwarding = selectedDispatch {
                                .forwarded
                            } else {
                                .stubbed
                            }
                        let appended = policy.invocationLedger.append(
                            method: methodIndex,
                            name: method.name,
                            origin: origin,
                            registrationSignature: entry.diagnosticSignature,
                            callStack: callStack,
                            startedAt: startedAt,
                            completionActions: entry.sideEffects.after.map { effect in
                                { effect(args) }
                            },
                            args: args,
                            argumentConventions: recordingArgumentConventions(for: method),
                            runtimePayloadRecorder: self
                        )
                        preparedMatch.matcherTransaction.commitCaptures()
                        let dispatch: PreparedDispatch =
                            switch selectedDispatch {
                                case .behavior(let behavior):
                                    .behavior(appended.token, behavior)
                                case .forwarding:
                                    .forwarding(appended.token)
                            }
                        return (
                            dispatch,
                            appended.waiters,
                            entry.sideEffects.before
                        )
                    }
            guard let (dispatch, waiters, beforeEffects) = committed else {
                continue
            }
            for effect in beforeEffects {
                effect(args)
            }
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
        method: RuntimeMethod,
        args: [Any],
        entries: [StubEntry]
    ) -> SelectedDispatch {
        guard case .fixedSequence(let results) = behavior else {
            return .behavior(behavior)
        }
        switch results.next() {
            case .value(let result):
                return .behavior(.fixed(result))
            case .delayed(let result, let delay, let clock):
                let cancellableDelay = method.isThrowing
                return .behavior(
                    .suspending { _ in
                        try await StubRecorder.deliverFixedResult(
                            result,
                            after: delay,
                            using: clock,
                            cancellableDelay: cancellableDelay
                        )
                    })
            case .faultInjection(let schedule):
                return .behavior(.fixed(schedule.next()))
            case .immediate(let handler):
                return .behavior(.immediate(handler))
            case .suspending(let handler):
                return .behavior(.suspending(handler))
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
            case .cancelAfter(let delay, let clock, let outcome):
                let isThrowing = method.isThrowing
                return .behavior(
                    .suspending { _ in
                        if isThrowing {
                            try await clock.sleep(for: delay)
                        } else {
                            await Task {
                                try? await clock.sleep(for: delay)
                            }.value
                        }
                        withUnsafeCurrentTask { task in
                            task?.cancel()
                        }
                        if let outcome {
                            return try outcome.get()
                        }
                        throw CancellationError()
                    }
                )
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
        using clock: any StubClock,
        cancellableDelay: Bool
    ) async throws -> Any {
        if cancellableDelay {
            try await clock.sleep(for: delay)
        } else {
            await Task { try? await clock.sleep(for: delay) }.value
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
        method: RuntimeMethod,
        args: [Any],
        callStack: [String]?,
        startedAt: ContinuousClock.Instant
    ) -> RecordedCallToken {
        let appended = withLockedPolicy {
            $0.invocationLedger.append(
                method: method.index,
                name: method.name,
                origin: .forwarded,
                callStack: callStack,
                startedAt: startedAt,
                args: args,
                argumentConventions: recordingArgumentConventions(for: method),
                runtimePayloadRecorder: self
            )
        }
        resumeWaiters(appended.waiters, returning: .changed)
        return appended.token
    }

    private func capturedCallStack() -> [String]? {
        #if os(WASI)
            return nil
        #else
            guard
                let limit = withLockedPolicy({ $0.callStackCaptureLimit })
            else {
                return nil
            }
            return Array(Thread.callStackSymbols.dropFirst(2).prefix(limit))
        #endif
    }

    func completeInvocation(
        _ token: RecordedCallToken,
        outcome: RecordedCallOutcome
    ) {
        let completion = withLockedPolicy {
            $0.invocationLedger.complete(token, outcome: outcome)
        }
        for action in completion.actions {
            action()
        }
        resumeWaiters(completion.waiters, returning: .changed)
    }

    private func recordedOutcome(
        for result: Result<Any, any Error>
    ) -> RecordedCallOutcome {
        switch result {
            case .success(let value): .returned(value)
            case .failure(let error): .threw(error)
        }
    }

    private func recordPlaceholder(method: Int, name: String, args: [Any]) {
        let recording = MatcherContext.takeRecording()
        var matchers = recording.matchers
        var matcherPositionsWereInferred = false
        let runtimeMethod = runtimeMethod(for: method)
        if matchers.isEmpty == false,
            let runtimeMethod,
            runtimeMethod.argumentIsVariadic.contains(true)
        {
            matchers = variadicMatchers(
                from: matchers,
                arguments: args,
                method: runtimeMethod
            )
        }
        if runtimeMethod?.argumentIsAutoclosure.contains(true) == true,
            matchers.count != args.count
        {
            fatalError(
                "[TestDoubles] Recording \(name) has an @autoclosure argument whose "
                    + "Match expression was not captured. An @autoclosure defers its "
                    + "body until the implementation invokes it, after TestDoubles must "
                    + "record the call. Create a closure-typed Match expression before "
                    + "the invocation inside the recording closure, then invoke that matcher "
                    + "inside the autoclosure. For example, declare a closure placeholder "
                    + "and `let matcher = Match.any(using: placeholder)` before returning "
                    + "$0.requirement(matcher())."
            )
        }
        if matchers.isEmpty == false,
            matchers.count != args.count,
            runtimeMethod?.argumentIsVariadic.contains(true) != true,
            let resolved = mixedLiteralMatchers(
                matchers: matchers,
                calibrations: recording.calibrations,
                arguments: args
            )
        {
            matchers = resolved
            matcherPositionsWereInferred = true
        }
        if matchers.isEmpty == false, matchers.count != args.count {
            let variadicGuidance =
                runtimeMethod?.argumentIsVariadic.contains(true) == true
                ? " A variadic parameter is one array at runtime; write one Match expression for each element in the recorded call."
                : ""
            fatalError(
                "[TestDoubles] Recording \(name) used \(matchers.count) Match expression(s) for "
                    + "\(args.count) argument(s), but their positions could not be determined safely. "
                    + "Rewrite each pinned literal with Match.equal(_:) or Match.identical(to:) so "
                    + "every argument has an explicit Match expression.\(variadicGuidance)"
            )
        }
        if runtimeMethod?.kind == .setter,
            args.count > 1,
            matchers.count == args.count,
            matcherPositionsWereInferred == false,
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
                matchers: matchers,
                matchesEmptyArgumentsExactly: args.isEmpty
                    && runtimeMethod?.argumentConventions.contains {
                        if case .methodGenericParameterPack = $0 { return true }
                        return false
                    } == true
            ),
            to: self
        )
    }

    /// Resolves a partial matcher list only when its placeholder values have
    /// one unique assignment to the decoded runtime arguments. A collision is
    /// intentionally rejected: guessing would silently install a matcher at
    /// the wrong argument position.
    private func mixedLiteralMatchers(
        matchers: [ParameterMatcher],
        calibrations: [RuntimeArgumentCalibration],
        arguments: [Any]
    ) -> [ParameterMatcher]? {
        guard matchers.count == calibrations.count else { return nil }

        let candidates = calibrations.map { calibration in
            arguments.indices.filter {
                calibration.matchesPlaceholderBytes(of: arguments[$0])
            }
        }
        guard candidates.allSatisfy({ $0.isEmpty == false }) else { return nil }

        func completeAssignment(
            excluding excludedEdge: (matcher: Int, argument: Int)? = nil
        ) -> [Int]? {
            var argumentOwners = [Int?](repeating: nil, count: arguments.count)

            func assign(_ matcherIndex: Int, visited: inout Set<Int>) -> Bool {
                for argumentIndex in candidates[matcherIndex] {
                    if excludedEdge?.matcher == matcherIndex,
                        excludedEdge?.argument == argumentIndex
                    {
                        continue
                    }
                    guard visited.insert(argumentIndex).inserted else { continue }
                    if let currentOwner = argumentOwners[argumentIndex] {
                        guard assign(currentOwner, visited: &visited) else { continue }
                    }
                    argumentOwners[argumentIndex] = matcherIndex
                    return true
                }
                return false
            }

            for matcherIndex in matchers.indices {
                var visited = Set<Int>()
                guard assign(matcherIndex, visited: &visited) else { return nil }
            }

            var assignment = [Int](repeating: -1, count: matchers.count)
            for (argumentIndex, matcherIndex) in argumentOwners.enumerated() {
                if let matcherIndex {
                    assignment[matcherIndex] = argumentIndex
                }
            }
            return assignment
        }

        guard let positions = completeAssignment() else { return nil }
        for (matcherIndex, argumentIndex) in positions.enumerated() {
            if completeAssignment(
                excluding: (matcher: matcherIndex, argument: argumentIndex)
            ) != nil {
                return nil
            }
        }

        var resolved = [ParameterMatcher?](repeating: nil, count: arguments.count)
        for (matcher, argumentIndex) in zip(matchers, positions) {
            resolved[argumentIndex] = matcher
        }
        for argumentIndex in arguments.indices where resolved[argumentIndex] == nil {
            resolved[argumentIndex] = literalMatcher(for: arguments[argumentIndex])
        }
        return resolved.compactMap { $0 }
    }

    private func variadicMatchers(
        from matchers: [ParameterMatcher],
        arguments: [Any],
        method: RuntimeMethod
    ) -> [ParameterMatcher] {
        guard arguments.count == method.arguments.count else { return matchers }

        var sourceIndex = matchers.startIndex
        var grouped: [ParameterMatcher] = []
        for (argument, isVariadic) in zip(arguments, method.argumentIsVariadic) {
            guard isVariadic else {
                guard sourceIndex < matchers.endIndex else { return matchers }
                grouped.append(matchers[sourceIndex])
                sourceIndex += 1
                continue
            }

            let elements = Mirror(reflecting: argument).children
            let endIndex = sourceIndex + elements.count
            guard endIndex <= matchers.endIndex else { return matchers }
            grouped.append(
                VariadicElementsMatcher(
                    elements: Array(matchers[sourceIndex ..< endIndex])
                )
            )
            sourceIndex = endIndex
        }
        return sourceIndex == matchers.endIndex ? grouped : matchers
    }

    private func recordingArgumentConventions(
        for method: RuntimeMethod
    ) -> [RuntimeValueConvention]? {
        method.argumentConventions.contains {
            $0 == .selfType || $0 == .optionalSelf
                || $0 == .nestedOptionalSelf || $0 == .arraySelf
                || $0 == .optionalArraySelf
                || $0 == .inoutSelf
        } ? method.argumentConventions : nil
    }

    // Sentinel value for capture mode returns.
    private var zeroValue: Any { 0 as Int }
}

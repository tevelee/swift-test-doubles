import Foundation

struct ModifyDispatchDescriptor: Sendable {
    let getterDispatchIndex: Int
    let setterDispatchIndex: Int
}

/// Records method calls and returns stubbed values.
/// Uses normal dispatch and task-local capture sessions shared by stubbing and
/// verification.
final class StubRecorder: @unchecked Sendable {
    private var methodCatalog: ManualMethodCatalog
    private var behaviorRegistry = StubBehaviorRegistry()
    private var invocationLedger = InvocationLedger()
    private weak var runtimeResourceOwner: AnyObject?
    private let allowsForwardingFallback: Bool

    /// The recorder is the only owner of the lock protecting its policy state.
    /// Matcher predicates, handlers, and waiter resumes always run after the
    /// lock is released. Captor commits share the invocation commit so capture,
    /// recording, and queued-result reservation have one ordering point.
    private let lock = NSLock()

    init(
        methods: [MethodDescriptor],
        modifyDispatchDescriptors: [Int: ModifyDispatchDescriptor] = [:],
        allowsForwardingFallback: Bool = false
    ) {
        methodCatalog = ManualMethodCatalog(
            methods: methods,
            modifyDispatchDescriptors: modifyDispatchDescriptors
        )
        self.allowsForwardingFallback = allowsForwardingFallback
    }

    enum Mode {
        case normal
        case capturing
    }

    enum EventualCallCountResult {
        case satisfied
        case timedOut(actualCount: Int)
        case cancelled
    }

    enum AsyncDispatch {
        case placeholder
        case immediate(Result<Any, any Error>)
        case suspending(([Any]) async throws -> Any)
        case forwarding
    }

    enum PreparedDispatch {
        case placeholder
        case behavior(StubEntry.Behavior)
        case forwarding
    }

    var mode: Mode {
        StubCaptureCoordinator.isCapturing(self) ? .capturing : .normal
    }

    // MARK: - Method catalog and runtime resources

    func runtimeMethod(for index: Int) -> MethodDescriptor? {
        // Locked because a manual stub's first forwarding of a requirement
        // appends to the catalog while other invocations may be reading.
        withLock { methodCatalog.method(at: index) }
    }

    func modifyDispatchMethods(
        forGetterIndex getterIndex: Int
    ) -> (getter: MethodDescriptor, setter: MethodDescriptor)? {
        withLock {
            methodCatalog.modifyDispatchMethods(forGetterIndex: getterIndex)
        }
    }

    func returnValueMatchesRuntimeType(_ value: Any, for methodIndex: Int) -> Bool {
        guard let method = runtimeMethod(for: methodIndex) else { return false }
        guard case .associatedType = method.result.dependency else { return true }

        func matches<Expected>(_ type: Expected.Type) -> Bool {
            value is Expected
        }
        return _openExistential(method.returnType, do: matches)
    }

    func requireReturnValueMatchesRuntimeType(
        _ value: Any,
        for methodIndex: Int
    ) {
        guard returnValueMatchesRuntimeType(value, for: methodIndex) else {
            let expected =
                runtimeMethod(for: methodIndex).map {
                    runtimeTypeName($0.returnType)
                } ?? "<missing method>"
            preconditionFailure(
                "[TestDoubles] Associated result must be \(expected), got \(type(of: value))."
            )
        }
    }

    func requireThrownErrorMatchesRuntimeType(
        _ error: any Error,
        for method: MethodDescriptor
    ) {
        guard let expectedType = method.typedErrorType else {
            return
        }

        func matches<Expected>(_ type: Expected.Type) -> Bool {
            error is Expected
        }
        guard _openExistential(expectedType, do: matches) else {
            fatalError(
                "[TestDoubles] Typed error must be \(expectedType), got \(type(of: error))."
            )
        }
    }

    func attachRuntimeResources(_ resources: AnyObject) {
        withLock {
            precondition(
                runtimeResourceOwner == nil,
                "[TestDoubles] Runtime resources may only be attached once."
            )
            runtimeResourceOwner = resources
        }
    }

    func makeRuntimePayload() -> StubPayload? {
        withLock { runtimeResourceOwner }.map(StubPayload.init(resources:))
    }

    // MARK: - Manual stub method interning

    /// Interns a manually-dispatched method, getter, or setter by identity.
    /// The visible signature remains the diagnostic name, while result type
    /// and effects keep legal Swift overloads in distinct recorder slots.
    func internManualMethod(
        signature: String,
        kind: StubRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
        internManualMethod(
            route: .implicit(signature),
            kind: kind,
            returnType: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    /// Interns a manually-dispatched requirement using either its legacy
    /// printed signature or a typed route discriminator.
    func internManualMethod(
        route: ManualMethodRouteIdentity,
        kind: StubRequirementKind,
        returnType: Any.Type,
        isAsync: Bool,
        isThrowing: Bool
    ) -> MethodDescriptor {
        withLock {
            methodCatalog.internManualMethod(
                route: route,
                kind: kind,
                returnType: returnType,
                isAsync: isAsync,
                isThrowing: isThrowing
            )
        }
    }

    // MARK: - Capture lifecycle

    func captureCalls(_ operation: () -> Void) -> [RecordedCall] {
        StubCaptureCoordinator.capture(recorder: self, operation)
    }

    func captureCalls(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async -> Void
    ) async -> [RecordedCall] {
        await StubCaptureCoordinator.capture(
            recorder: self,
            isolation: isolation,
            operation
        )
    }

    // MARK: - Dispatch

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

    func addAsyncStub(
        method: Int,
        matchers: [ParameterMatcher],
        handler: @escaping ([Any]) async throws -> Any
    ) {
        guard runtimeMethod(for: method)?.isAsync == true else {
            preconditionFailure(
                "[TestDoubles] Suspending handlers require an async Stub requirement. "
                    + "Synchronous requirements support only immediate handlers."
            )
        }
        addEntry(method: method, matchers: matchers, behavior: .suspending(handler))
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

        guard let entries = withLock({ behaviorRegistry.entries(for: methodIndex) }) else {
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
        guard let entry = StubBehaviorRegistry.firstMatchingEntry(for: args, in: entries) else {
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

        let (behavior, waiters) = withLock {
            StubBehaviorRegistry.commitCaptures(in: args, against: entry.matchers)
            let waiters = invocationLedger.append(
                method: methodIndex,
                name: method.name,
                args: args
            )
            let behavior: StubEntry.Behavior
            switch entry.behavior {
                case .fixedSequence(let results):
                    switch results.next() {
                        case .value(let result):
                            behavior = .fixed(result)
                        case .delayed(let result, let delay):
                            let cancellableDelay = method.isThrowing
                            behavior = .suspending { _ in
                                try await StubRecorder.deliverFixedResult(
                                    result,
                                    after: delay,
                                    cancellableDelay: cancellableDelay
                                )
                            }
                        case .fatal(let message):
                            fatalError(
                                diagnosticMessage(
                                    title: message.map { "Explicit stub failure: \($0)" }
                                        ?? "Explicit stub failure",
                                    method: method,
                                    args: args,
                                    entries: entries
                                ))
                    }
                default:
                    behavior = entry.behavior
            }
            return (behavior, waiters)
        }
        resume(waiters, returning: .changed)
        return .behavior(behavior)
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

    private func recordForwardedInvocation(
        method: MethodDescriptor,
        args: [Any]
    ) {
        let waiters = withLock {
            invocationLedger.append(
                method: method.index,
                name: method.name,
                args: args
            )
        }
        resume(waiters, returning: .changed)
    }

    // MARK: - Stub registration

    func addReturnValue(
        method: Int,
        matchers: [ParameterMatcher],
        value: Any
    ) {
        addEntry(method: method, matchers: matchers, behavior: .fixed(.success(value)))
    }

    func addFixedResultSequence(
        method: Int,
        matchers: [ParameterMatcher],
        answers: [(QueuedAnswer, RepeatCount)]
    ) -> ConsumableResults {
        let sequence = ConsumableResults(answers)
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .fixedSequence(sequence)
        )
        return sequence
    }

    func addStub(
        method: Int,
        matchers: [ParameterMatcher],
        returnValue: @escaping @Sendable ([Any]) throws -> Any
    ) {
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .immediate(returnValue)
        )
    }

    private func addEntry(
        method: Int,
        matchers: [ParameterMatcher],
        behavior: StubEntry.Behavior
    ) {
        withLock {
            behaviorRegistry.add(
                method: method,
                matchers: matchers,
                diagnosticSignature: methodCatalog.diagnosticSignature(
                    method: method,
                    matchers: matchers
                ),
                behavior: behavior
            )
        }
    }

    // MARK: - Verification queries

    func clearRecordedInvocations() {
        let waiters = withLock { invocationLedger.clear() }
        resume(waiters, returning: .changed)
    }

    /// Returns an ordered-verification diagnostic, or `nil` after committing
    /// captures for a fully matched expectation sequence.
    func orderedVerificationFailure(for expectations: [RecordedCall]) -> String? {
        // Predicates are user code. Snapshot under the recorder lock, then run
        // every matcher after releasing it.
        let calls = withLock { invocationLedger.allCalls }
        var searchStart = calls.startIndex
        var matches: [(expectation: RecordedCall, actual: RecordedCall)] = []

        for (expectationIndex, expectation) in expectations.enumerated() {
            let matchers = expectation.resolvedMatchers
            var matchedIndex: Int?
            if searchStart < calls.endIndex {
                matchedIndex = calls[searchStart...].firstIndex { call in
                    call.methodIndex == expectation.methodIndex
                        && StubBehaviorRegistry.argumentsMatch(call.args, against: matchers)
                }
            }

            guard let matchedIndex else {
                return StubRecorderDiagnostics.orderedVerificationFailure(
                    expectationIndex: expectationIndex,
                    expectation: expectation,
                    calls: calls
                )
            }

            matches.append((expectation, calls[matchedIndex]))
            searchStart = calls.index(after: matchedIndex)
        }

        // Captors are transactional for an ordered sequence: a later missing
        // expectation must not leave values committed by earlier matches.
        for match in matches {
            StubBehaviorRegistry.commitCaptures(
                in: match.actual.args,
                against: match.expectation.resolvedMatchers
            )
        }
        markVerified(matches.map(\.actual))
        return nil
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

    // Sentinel value for capture mode returns.
    private var zeroValue: Any { 0 as Int }

    @discardableResult
    private func withLock<Result, Failure: Error>(
        _ operation: () throws(Failure) -> Result
    ) throws(Failure) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

// MARK: - Event-driven verification

extension StubRecorder {
    func verificationMatches(
        method: Int,
        matchers: [ParameterMatcher] = []
    ) -> [RecordedCall] {
        matchingCalls(method: method, matchers: matchers)
    }

    func commitSuccessfulVerification(
        of calls: [RecordedCall],
        against matchers: [ParameterMatcher]
    ) {
        for call in calls {
            StubBehaviorRegistry.commitCaptures(in: call.args, against: matchers)
        }
        markVerified(calls)
    }

    func unverifiedInteractionsDiagnostic() -> String? {
        StubRecorderDiagnostics.unverifiedInteractions(
            withLock { invocationLedger.unverifiedCalls() }
        )
    }

    private func markVerified(_ calls: [RecordedCall]) {
        withLock { invocationLedger.markVerified(calls) }
    }

    func waitForCallCount(
        recording: RecordedCall,
        minimumCount: Int,
        timeout: Duration
    ) async -> EventualCallCountResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let method = recording.methodIndex
        let matchers = recording.resolvedMatchers

        while true {
            // Matcher predicates are user code. Snapshot both the calls and
            // generation under the lock, then evaluate them after releasing it.
            let snapshot = withLock { invocationLedger.snapshot(for: method) }
            let matches = matchingCalls(
                method: method,
                matchers: matchers,
                in: snapshot.calls
            )
            if matches.count >= minimumCount {
                commitSuccessfulVerification(of: matches, against: matchers)
                return .satisfied
            }
            if Task.isCancelled {
                return .cancelled
            }
            if deadline <= clock.now {
                return .timedOut(actualCount: matches.count)
            }

            switch await waitForCall(after: snapshot.generation, until: deadline) {
                case .changed:
                    continue
                case .timedOut:
                    // Re-evaluate once after the timeout wins its waiter race.
                    // A call that appended at the boundary may have advanced
                    // the generation before this task resumed.
                    let finalMatches = matchingCalls(method: method, matchers: matchers)
                    if finalMatches.count >= minimumCount {
                        commitSuccessfulVerification(of: finalMatches, against: matchers)
                        return .satisfied
                    }
                    return .timedOut(actualCount: finalMatches.count)
                case .cancelled:
                    return .cancelled
            }
        }
    }

    private func matchingCalls(
        method: Int,
        matchers: [ParameterMatcher]
    ) -> [RecordedCall] {
        matchingCalls(
            method: method,
            matchers: matchers,
            in: withLock { invocationLedger.allCalls }
        )
    }

    private func matchingCalls(
        method: Int,
        matchers: [ParameterMatcher],
        in calls: [RecordedCall]
    ) -> [RecordedCall] {
        calls.filter { call in
            call.methodIndex == method
                && (matchers.isEmpty
                    || StubBehaviorRegistry.argumentsMatch(call.args, against: matchers))
        }
    }

    private func waitForCall(
        after generation: InvocationLedgerGeneration,
        until deadline: ContinuousClock.Instant
    ) async -> InvocationLedgerWaitOutcome {
        let waiterID = withLock { invocationLedger.allocateWaiterID() }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiter = InvocationLedgerWaiter(continuation: continuation)
                let immediateOutcome = withLock {
                    invocationLedger.register(
                        waiter,
                        id: waiterID,
                        after: generation,
                        isCancelled: Task.isCancelled
                    )
                }

                if let immediateOutcome {
                    continuation.resume(returning: immediateOutcome)
                    return
                }

                let timeoutTask = Task { [weak self] in
                    do {
                        try await ContinuousClock().sleep(until: deadline)
                    } catch {
                        return
                    }
                    self?.resolveCallWaiter(waiterID, returning: .timedOut)
                }
                let attached = withLock {
                    invocationLedger.attachTimeoutTask(timeoutTask, to: waiterID)
                }
                if attached == false {
                    timeoutTask.cancel()
                }
            }
        } onCancel: {
            resolveCallWaiter(waiterID, returning: .cancelled)
        }
    }

    private func resolveCallWaiter(
        _ waiterID: UInt64,
        returning outcome: InvocationLedgerWaitOutcome
    ) {
        guard let waiter = withLock({ invocationLedger.removeWaiter(id: waiterID) }) else {
            return
        }
        waiter.timeoutTask?.cancel()
        waiter.resume(returning: outcome)
    }

    private func resume(
        _ waiters: [InvocationLedgerWaiter],
        returning outcome: InvocationLedgerWaitOutcome
    ) {
        for waiter in waiters {
            waiter.timeoutTask?.cancel()
            waiter.resume(returning: outcome)
        }
    }
}

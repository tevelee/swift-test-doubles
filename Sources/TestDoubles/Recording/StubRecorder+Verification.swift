import Foundation

struct PreparedRecordedCallMatch {
    let call: RecordedCall
    let matcherTransaction: PreparedMatcherTransaction
}

extension StubRecorder {
    func forwardedVerificationMatches(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool
    ) -> [RecordedCall] {
        verificationMatches(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
        ).filter { $0.origin == .forwarded }
    }

    func clearRecordedInvocations() {
        let waiters = withLockedPolicy { $0.invocationLedger.clear() }
        resumeWaiters(waiters, returning: .changed)
    }

    /// Returns an ordered-verification diagnostic, or `nil` after committing
    /// captures for a fully matched expectation sequence.
    func orderedVerificationFailure(for expectations: [RecordedCall]) -> String? {
        // Predicates are user code. Snapshot under the recorder lock, then run
        // every matcher after releasing it.
        let calls = withLockedPolicy { $0.invocationLedger.allCalls }
        var searchStart = calls.startIndex
        var matches: [PreparedRecordedCallMatch] = []

        for (expectationIndex, expectation) in expectations.enumerated() {
            let matchers = expectation.resolvedMatchers
            var preparedMatch: (index: Int, transaction: PreparedMatcherTransaction)?
            if searchStart < calls.endIndex {
                for index in calls[searchStart...].indices {
                    let call = calls[index]
                    guard call.methodIndex == expectation.methodIndex else { continue }
                    if let transaction = StubBehaviorRegistry.prepareArgumentsMatch(
                        call.args,
                        against: matchers,
                        matchesEmptyArgumentsExactly: expectation.matchesEmptyArgumentsExactly
                    ) {
                        preparedMatch = (index, transaction)
                        break
                    }
                }
            }

            guard let preparedMatch else {
                return StubRecorderDiagnostics.orderedVerificationFailure(
                    expectationIndex: expectationIndex,
                    expectation: expectation,
                    calls: calls
                )
            }

            matches.append(
                PreparedRecordedCallMatch(
                    call: calls[preparedMatch.index],
                    matcherTransaction: preparedMatch.transaction
                ))
            searchStart = calls.index(after: preparedMatch.index)
        }

        // Captors are transactional for an ordered sequence: a later missing
        // expectation must not leave values committed by earlier matches.
        for match in matches {
            match.matcherTransaction.commitCaptures()
        }
        markVerified(matches.map(\.call))
        return nil
    }

    /// Returns an exact-timeline verification diagnostic, or `nil` after
    /// committing captures for a sequence that accounts for every call.
    func exactOrderedVerificationFailure(for expectations: [RecordedCall]) -> String? {
        let calls = withLockedPolicy { $0.invocationLedger.allCalls }
        guard calls.count == expectations.count else {
            return StubRecorderDiagnostics.exactOrderedVerificationCountFailure(
                expectations: expectations,
                calls: calls
            )
        }

        var matches: [PreparedRecordedCallMatch] = []
        for (index, pair) in zip(expectations, calls).enumerated() {
            let (expectation, call) = pair
            guard
                call.methodIndex == expectation.methodIndex,
                let transaction = StubBehaviorRegistry.prepareArgumentsMatch(
                    call.args,
                    against: expectation.resolvedMatchers,
                    matchesEmptyArgumentsExactly: expectation.matchesEmptyArgumentsExactly
                )
            else {
                return StubRecorderDiagnostics.exactOrderedVerificationFailure(
                    expectationIndex: index,
                    expectation: expectation,
                    actual: call,
                    calls: calls
                )
            }
            matches.append(
                PreparedRecordedCallMatch(call: call, matcherTransaction: transaction)
            )
        }

        for match in matches {
            match.matcherTransaction.commitCaptures()
        }
        markVerified(matches.map(\.call))
        return nil
    }

    func verificationMatches(
        method: Int,
        matchers: [ParameterMatcher] = [],
        matchesEmptyArgumentsExactly: Bool = false
    ) -> [RecordedCall] {
        preparedVerificationMatches(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
        ).map(\.call)
    }

    func preparedVerificationMatches(
        method: Int,
        matchers: [ParameterMatcher] = [],
        matchesEmptyArgumentsExactly: Bool = false
    ) -> [PreparedRecordedCallMatch] {
        matchingCalls(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
        )
    }

    /// Returns the earliest recorded call matching `recording` whose global
    /// sequence stamp is later than `cursor`. Matcher predicates are user
    /// code, so the calls are snapshotted under the lock and evaluated after
    /// releasing it.
    func earliestOrderedMatch(
        recording: RecordedCall,
        after cursor: UInt64
    ) -> PreparedRecordedCallMatch? {
        let calls = withLockedPolicy { $0.invocationLedger.allCalls }
        let matchers = recording.resolvedMatchers
        for call in calls {
            guard
                let sequence = call.sequence,
                sequence > cursor,
                call.methodIndex == recording.methodIndex,
                let transaction = StubBehaviorRegistry.prepareArgumentsMatch(
                    call.args,
                    against: matchers,
                    matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
                )
            else {
                continue
            }
            return PreparedRecordedCallMatch(
                call: call,
                matcherTransaction: transaction
            )
        }
        return nil
    }

    func commitSuccessfulVerification(of matches: [PreparedRecordedCallMatch]) {
        for match in matches {
            match.matcherTransaction.commitCaptures()
        }
        markVerified(matches.map(\.call))
    }

    func interactionLog() -> String {
        StubRecorderDiagnostics.interactionLog(
            withLockedPolicy { $0.invocationLedger.allCalls }
        )
    }

    func unverifiedInteractionsDiagnostic() -> String? {
        StubRecorderDiagnostics.unverifiedInteractions(
            withLockedPolicy { $0.invocationLedger.unverifiedCalls() }
        )
    }

    func unusedRegistrationsDiagnostic() -> String? {
        let signatures = withLockedPolicy {
            $0.behaviorRegistry.unusedRegistrationSignatures()
        }
        guard signatures.isEmpty == false else { return nil }
        return "Unused stub registrations (never matched by any call):\n"
            + signatures.map { "  - \($0)" }.joined(separator: "\n")
    }

    func latestRecordedCallID() -> UInt64? {
        withLockedPolicy { $0.invocationLedger.latestRecordedCallID }
    }

    /// Waits for the next matching call recorded after `lastSeenCallID`.
    ///
    /// Invocation streams are observational, so their matcher transactions
    /// intentionally do not commit captures or verification state.
    func nextMatchingInvocation(
        after lastSeenCallID: UInt64?,
        matching recording: RecordedCall
    ) async -> RecordedCall? {
        let method = recording.methodIndex
        let matchers = recording.resolvedMatchers

        while Task.isCancelled == false {
            let snapshot = withLockedPolicy {
                $0.invocationLedger.snapshot(for: method)
            }
            if let next = matchingCalls(
                method: method,
                matchers: matchers,
                matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
                in: snapshot.calls
            ).first(where: { match in
                guard let callID = match.call.id else { return false }
                guard let lastSeenCallID else { return true }
                return callID > lastSeenCallID
            }) {
                return next.call
            }

            guard await waitForCall(after: snapshot.generation) == .changed else {
                return nil
            }
        }
        return nil
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
            let snapshot = withLockedPolicy {
                $0.invocationLedger.snapshot(for: method)
            }
            let matches = matchingCalls(
                method: method,
                matchers: matchers,
                matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly,
                in: snapshot.calls
            )
            if matches.count >= minimumCount {
                commitSuccessfulVerification(of: matches)
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
                    let finalMatches = matchingCalls(
                        method: method,
                        matchers: matchers,
                        matchesEmptyArgumentsExactly: recording.matchesEmptyArgumentsExactly
                    )
                    if finalMatches.count >= minimumCount {
                        commitSuccessfulVerification(of: finalMatches)
                        return .satisfied
                    }
                    return .timedOut(actualCount: finalMatches.count)
                case .cancelled:
                    return .cancelled
            }
        }
    }

    private func markVerified(_ calls: [RecordedCall]) {
        withLockedPolicy { $0.invocationLedger.markVerified(calls) }
    }

    private func matchingCalls(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false
    ) -> [PreparedRecordedCallMatch] {
        matchingCalls(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            in: withLockedPolicy { $0.invocationLedger.allCalls }
        )
    }

    private func matchingCalls(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool,
        in calls: [RecordedCall]
    ) -> [PreparedRecordedCallMatch] {
        calls.compactMap { call in
            guard
                call.methodIndex == method,
                let transaction = StubBehaviorRegistry.prepareArgumentsMatch(
                    call.args,
                    against: matchers,
                    matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
                )
            else {
                return nil
            }
            return PreparedRecordedCallMatch(
                call: call,
                matcherTransaction: transaction
            )
        }
    }

    private func waitForCall(
        after generation: InvocationLedgerGeneration,
        until deadline: ContinuousClock.Instant
    ) async -> InvocationLedgerWaitOutcome {
        let waiterID = withLockedPolicy {
            $0.invocationLedger.allocateWaiterID()
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiter = InvocationLedgerWaiter(continuation: continuation)
                let immediateOutcome = withLockedPolicy {
                    $0.invocationLedger.register(
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
                let attached = withLockedPolicy {
                    $0.invocationLedger.attachTimeoutTask(timeoutTask, to: waiterID)
                }
                if attached == false {
                    timeoutTask.cancel()
                }
            }
        } onCancel: {
            resolveCallWaiter(waiterID, returning: .cancelled)
        }
    }

    private func waitForCall(
        after generation: InvocationLedgerGeneration
    ) async -> InvocationLedgerWaitOutcome {
        let waiterID = withLockedPolicy {
            $0.invocationLedger.allocateWaiterID()
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let waiter = InvocationLedgerWaiter(continuation: continuation)
                let immediateOutcome = withLockedPolicy {
                    $0.invocationLedger.register(
                        waiter,
                        id: waiterID,
                        after: generation,
                        isCancelled: Task.isCancelled
                    )
                }
                if let immediateOutcome {
                    continuation.resume(returning: immediateOutcome)
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
        guard
            let waiter = withLockedPolicy({
                $0.invocationLedger.removeWaiter(id: waiterID)
            })
        else {
            return
        }
        waiter.timeoutTask?.cancel()
        waiter.resume(returning: outcome)
    }
}

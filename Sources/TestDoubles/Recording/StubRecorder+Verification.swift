import Foundation

extension StubRecorder {
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
        var matches: [(expectation: RecordedCall, actual: RecordedCall)] = []

        for (expectationIndex, expectation) in expectations.enumerated() {
            let matchers = expectation.resolvedMatchers
            var matchedIndex: Int?
            if searchStart < calls.endIndex {
                matchedIndex = calls[searchStart...].firstIndex { call in
                    call.methodIndex == expectation.methodIndex
                        && StubBehaviorRegistry.argumentsMatch(
                            call.args,
                            against: matchers
                        )
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

    func verificationMatches(
        method: Int,
        matchers: [ParameterMatcher] = []
    ) -> [RecordedCall] {
        matchingCalls(method: method, matchers: matchers)
    }

    /// Returns the earliest recorded call matching `recording` whose global
    /// sequence stamp is later than `cursor`. Matcher predicates are user
    /// code, so the calls are snapshotted under the lock and evaluated after
    /// releasing it.
    func earliestOrderedMatch(
        recording: RecordedCall,
        after cursor: UInt64
    ) -> RecordedCall? {
        let calls = withLockedPolicy { $0.invocationLedger.allCalls }
        let matchers = recording.resolvedMatchers
        return calls.first { call in
            guard let sequence = call.sequence, sequence > cursor else { return false }
            return call.methodIndex == recording.methodIndex
                && (matchers.isEmpty
                    || StubBehaviorRegistry.argumentsMatch(
                        call.args,
                        against: matchers
                    ))
        }
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
                    let finalMatches = matchingCalls(
                        method: method,
                        matchers: matchers
                    )
                    if finalMatches.count >= minimumCount {
                        commitSuccessfulVerification(
                            of: finalMatches,
                            against: matchers
                        )
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
        matchers: [ParameterMatcher]
    ) -> [RecordedCall] {
        matchingCalls(
            method: method,
            matchers: matchers,
            in: withLockedPolicy { $0.invocationLedger.allCalls }
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
                    || StubBehaviorRegistry.argumentsMatch(
                        call.args,
                        against: matchers
                    ))
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

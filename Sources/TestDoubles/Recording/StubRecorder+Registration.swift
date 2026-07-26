import IssueReporting

extension StubRecorder {
    func addAsyncStub(
        method: Int,
        matchers: [ParameterMatcher],
        location: StubSourceLocation? = nil,
        handler: @escaping ([Any]) async throws -> Any
    ) {
        guard runtimeMethod(for: method)?.isAsync == true else {
            preconditionFailure(
                "[TestDoubles] Suspending handlers require an async Stub requirement. "
                    + "Synchronous requirements support only immediate handlers."
            )
        }
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .suspending(handler),
            location: location
        )
    }

    func addReturnValue(
        method: Int,
        matchers: [ParameterMatcher],
        location: StubSourceLocation? = nil,
        value: Any
    ) {
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .fixed(.success(value)),
            location: location
        )
    }

    func addFixedResultSequence(
        method: Int,
        matchers: [ParameterMatcher],
        location: StubSourceLocation? = nil,
        answers: [(QueuedAnswer, RepeatCount)]
    ) -> ConsumableResults {
        let sequence = ConsumableResults(answers)
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .fixedSequence(sequence),
            location: location
        )
        return sequence
    }

    func addStub(
        method: Int,
        matchers: [ParameterMatcher],
        location: StubSourceLocation? = nil,
        returnValue: @escaping @Sendable ([Any]) throws -> Any
    ) {
        addEntry(
            method: method,
            matchers: matchers,
            behavior: .immediate(returnValue),
            location: location
        )
    }

    func clearConfiguredBehaviors() {
        withLockedPolicy { $0.behaviorRegistry.removeAll() }
    }

    private func addEntry(
        method: Int,
        matchers: [ParameterMatcher],
        behavior: StubEntry.Behavior,
        location: StubSourceLocation?
    ) {
        let shadow: (new: String, shadowedBy: String)? = withLockedPolicy {
            let newSignature = $0.methodCatalog.diagnosticSignature(
                method: method,
                matchers: matchers
            )
            let shadowedBy = $0.behaviorRegistry.shadowingSignature(
                forMethod: method,
                newMatchers: matchers
            )
            $0.behaviorRegistry.add(
                method: method,
                matchers: matchers,
                diagnosticSignature: newSignature,
                behavior: behavior
            )
            return shadowedBy.map { (newSignature, $0) }
        }

        // Predicates and issue reporting are user-visible work, kept off the
        // recorder lock.
        if let shadow, let location {
            reportIssue(
                "[TestDoubles] Unreachable stub registration: \(shadow.new) can never "
                    + "match because the earlier registration \(shadow.shadowedBy) accepts "
                    + "every call it would. Under first-match-wins, register specific "
                    + "matchers before broad fallbacks.",
                fileID: location.fileID,
                filePath: location.filePath,
                line: location.line,
                column: location.column
            )
        }
    }
}

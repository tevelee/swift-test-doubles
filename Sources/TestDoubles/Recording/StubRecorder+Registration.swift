import IssueReporting

private struct StubEntryRegistrationResult {
    let signature: String
    let scenarioName: String?
    let shadowedBy: StubBehaviorRegistry.ShadowingRegistration?
}

extension StubRecorder {
    func addAsyncStub(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
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
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            behavior: .suspending(handler),
            location: location
        )
    }

    func addReturnValue(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
        location: StubSourceLocation? = nil,
        value: Any
    ) {
        addEntry(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            behavior: .fixed(.success(value)),
            location: location
        )
    }

    func addFixedResultSequence(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
        location: StubSourceLocation? = nil,
        answers: [(QueuedAnswer, RepeatCount)]
    ) -> ConsumableResults {
        let sequence = ConsumableResults(answers)
        addEntry(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            behavior: .fixedSequence(sequence),
            location: location
        )
        return sequence
    }

    func addStub(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool = false,
        location: StubSourceLocation? = nil,
        returnValue: @escaping @Sendable ([Any]) throws -> Any
    ) {
        addEntry(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
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
        matchesEmptyArgumentsExactly: Bool,
        behavior: StubEntry.Behavior,
        location: StubSourceLocation?
    ) {
        let scenarioName = TestDoubleScenarioContext.name
        let registration = registerEntry(
            method: method,
            matchers: matchers,
            matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
            behavior: behavior,
            location: location,
            scenarioName: scenarioName
        )

        // Predicates and issue reporting are user-visible work, kept off the
        // recorder lock.
        if let location {
            reportShadowing(registration, at: location)
        }
    }

    private func registerEntry(
        method: Int,
        matchers: [ParameterMatcher],
        matchesEmptyArgumentsExactly: Bool,
        behavior: StubEntry.Behavior,
        location: StubSourceLocation?,
        scenarioName: String?
    ) -> StubEntryRegistrationResult {
        withLockedPolicy { policy -> StubEntryRegistrationResult in
            let signature = policy.methodCatalog.diagnosticSignature(
                method: method,
                matchers: matchers
            )
            let shadowedBy = policy.behaviorRegistry.shadowingSignature(
                forMethod: method,
                newMatchers: matchers,
                newMatchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
            )
            policy.behaviorRegistry.add(
                method: method,
                matchers: matchers,
                matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
                diagnosticSignature: signature,
                scenarioName: scenarioName,
                sourceLocation: location,
                behavior: behavior
            )
            return StubEntryRegistrationResult(
                signature: signature,
                scenarioName: scenarioName,
                shadowedBy: shadowedBy
            )
        }
    }

    private func reportShadowing(
        _ registration: StubEntryRegistrationResult,
        at location: StubSourceLocation
    ) {
        guard let shadowedBy = registration.shadowedBy else { return }
        let newScenario =
            registration.scenarioName.map {
                " while applying scenario '\($0)'"
            } ?? ""
        let previousScenario =
            shadowedBy.scenarioName.map {
                " (from scenario '\($0)')"
            } ?? ""
        let message =
            "[TestDoubles] Unreachable stub registration\(newScenario): \(registration.signature) can never "
            + "match because the earlier registration \(shadowedBy.signature)\(previousScenario) accepts "
            + "every call it would. Under first-match-wins, register specific "
            + "matchers before broad fallbacks."
        reportIssue(
            message,
            fileID: location.fileID,
            filePath: location.filePath,
            line: location.line,
            column: location.column
        )
    }
}

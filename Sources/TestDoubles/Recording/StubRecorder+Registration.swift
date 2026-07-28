import IssueReporting

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
        let shadow: (new: String, scenario: String?, shadowedBy: StubBehaviorRegistry.ShadowingRegistration)? = withLockedPolicy {
            let newSignature = $0.methodCatalog.diagnosticSignature(
                method: method,
                matchers: matchers
            )
            let shadowedBy = $0.behaviorRegistry.shadowingSignature(
                forMethod: method,
                newMatchers: matchers,
                newMatchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly
            )
            $0.behaviorRegistry.add(
                method: method,
                matchers: matchers,
                matchesEmptyArgumentsExactly: matchesEmptyArgumentsExactly,
                diagnosticSignature: newSignature,
                scenarioName: scenarioName,
                sourceLocation: location,
                behavior: behavior
            )
            return shadowedBy.map { (newSignature, scenarioName, $0) }
        }

        // Predicates and issue reporting are user-visible work, kept off the
        // recorder lock.
        if let shadow, let location {
            let newScenario = shadow.scenario.map { " while applying scenario '\($0)'" } ?? ""
            let previousScenario = shadow.shadowedBy.scenarioName.map {
                " (from scenario '\($0)')"
            } ?? ""
            reportIssue(
                "[TestDoubles] Unreachable stub registration\(newScenario): \(shadow.new) can never "
                    + "match because the earlier registration \(shadow.shadowedBy.signature)\(previousScenario) accepts "
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

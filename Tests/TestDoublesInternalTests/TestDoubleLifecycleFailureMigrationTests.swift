import Testing
@testable import TestDoubles

@Suite struct TestDoubleLifecycleFailureMigrationTests {
    @Test func recordingCardinalityFailuresRetainStructuredCountsAndExactRendering() {
        let empty = RecordingCardinalityFailure.noRecordedRequirement.testDoubleFailure
        let multiple = RecordingCardinalityFailure.multipleRecordedRequirements(
            count: 2
        ).testDoubleFailure

        #expect(empty.phase == .recording)
        #expect(empty.code == .noRecordedRequirement)
        #expect(empty.context.fields == [.init(key: .recordedRequirementCount, value: "0")])
        #expect(
            empty.description
                == "[TestDoubles] The recording closure did not invoke a protocol requirement. "
                + "Call exactly one requirement inside `when` or `verify`. "
                + "If this was a method declared only in a protocol extension, Swift dispatches "
                + "it statically and TestDoubles cannot intercept it; declare it as a protocol "
                + "requirement instead."
        )

        #expect(multiple.phase == .recording)
        #expect(multiple.code == .multipleRecordedRequirements)
        #expect(multiple.context.fields == [.init(key: .recordedRequirementCount, value: "2")])
        #expect(
            multiple.description
                == "[TestDoubles] The recording closure invoked 2 protocol requirements, "
                + "but `when` and `verify` accept exactly one. Split them into separate operations; "
                + "use `verifyInOrder` when checking an ordered sequence."
        )
    }

    @Test func configurationFailuresRetainExactRenderingAndActionableFields() {
        assertConfigurationFailure(
            .missingRecordedRequirement,
            code: .missingConfiguredRequirement,
            fields: [],
            description: "[TestDoubles] The recording closure must invoke a requirement."
        )
        assertConfigurationFailure(
            .requiresThrowingRequirement(feature: "thenThrow"),
            code: .requiresThrowingRequirement,
            fields: [.init(key: .feature, value: "thenThrow")],
            description: "[TestDoubles] thenThrow requires a throwing requirement."
        )
        assertConfigurationFailure(
            .requiresNonnegativeDelay(feature: "after:"),
            code: .requiresNonnegativeDelay,
            fields: [.init(key: .feature, value: "after:")],
            description: "[TestDoubles] after: requires a nonnegative delay."
        )
        assertConfigurationFailure(
            .requiresNonnegativeDelay(feature: "thenCancel(after:)"),
            code: .requiresNonnegativeDelay,
            fields: [.init(key: .feature, value: "thenCancel(after:)")],
            description: "[TestDoubles] thenCancel(after:) requires a nonnegative delay."
        )
        assertConfigurationFailure(
            .requiresForwardingTarget(feature: "thenForward"),
            code: .requiresForwardingTarget,
            fields: [
                .init(key: .feature, value: "thenForward"),
                .init(key: .requiredDoubleKind, value: "Spy")
            ],
            description: "[TestDoubles] thenForward requires a Spy with a forwarding "
                + "target; this test double has none."
        )
        assertConfigurationFailure(
            .requiresExplicitCancellationValue(feature: "thenAwaitCancellation"),
            code: .requiresExplicitCancellationValue,
            fields: [.init(key: .feature, value: "thenAwaitCancellation")],
            description: "[TestDoubles] thenAwaitCancellation on a non-throwing requirement "
                + "with a result needs a value to complete with; use "
                + "thenAwaitCancellation(returning:)."
        )
        assertConfigurationFailure(
            .requiresAsyncRequirement(
                feature: "thenNeverReturn",
                requirement: "load()"
            ),
            code: .requiresAsyncRequirement,
            fields: [
                .init(key: .feature, value: "thenNeverReturn"),
                .init(key: .requirement, value: "load()")
            ],
            description: "[TestDoubles] thenNeverReturn requires an async requirement; "
                + "load() completes synchronously."
        )
    }

    private func assertConfigurationFailure(
        _ failure: StubConfigurationFailure,
        code: TestDoubleFailure.Code,
        fields: [TestDoubleFailure.Context.Field],
        description: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let structuredFailure = failure.testDoubleFailure

        #expect(structuredFailure.phase == .configuration, sourceLocation: sourceLocation)
        #expect(structuredFailure.code == code, sourceLocation: sourceLocation)
        #expect(structuredFailure.context.fields == fields, sourceLocation: sourceLocation)
        #expect(structuredFailure.description == description, sourceLocation: sourceLocation)
    }
}

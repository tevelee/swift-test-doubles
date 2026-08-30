import Testing
@testable import TestDoubles

@Suite struct TestDoubleFailureTests {
    @Test func phasesCoverTheTestDoubleLifecycle() {
        #expect(
            TestDoubleFailure.Phase.allCases.map(\.rawValue) == [
                "construction",
                "recording",
                "configuration",
                "dispatch",
                "verification"
            ]
        )
    }

    @Test func contextRetainsFieldsAndSourceLocationWithoutChangingRendering() {
        let location = StubSourceLocation(
            fileID: "FeatureTests/FeatureTests.swift",
            filePath: "/tmp/FeatureTests.swift",
            line: 42,
            column: 7
        )
        let failure = TestDoubleFailure(
            phase: .recording,
            code: .recordingFailed,
            context: TestDoubleFailure.Context(
                message: "Could not record the invocation.",
                fields: [
                    .init(key: "requirement", value: "load(id:)"),
                    .init(key: "argumentCount", value: "1")
                ],
                sourceLocation: location
            )
        )

        #expect(failure.description == "Could not record the invocation.")
        #expect(failure.phase == .recording)
        #expect(failure.code.rawValue == "recording.failed")
        #expect(failure.context.fields[0].key == "requirement")
        #expect(failure.context.fields[0].value == "load(id:)")
        #expect(failure.context.sourceLocation?.line == 42)
        #expect(failure.context.sourceLocation?.column == 7)
    }

    @Test(arguments: [
        (
            TestDoubleFailure.Recovery.inline("Try a different value."),
            "The value is invalid. Try a different value."
        ),
        (
            TestDoubleFailure.Recovery.nextLine("Recovery: Register a behavior."),
            "No behavior matched.\nRecovery: Register a behavior."
        )
    ])
    func rendererPlacesRecovery(
        recovery: TestDoubleFailure.Recovery,
        expected: String
    ) {
        let failure = TestDoubleFailure(
            phase: .configuration,
            code: .invalidConfiguration,
            context: .init(
                message: recovery.placement == .inline
                    ? "The value is invalid."
                    : "No behavior matched."),
            recovery: recovery
        )

        #expect(failure.description == expected)
    }

    @Test func stubErrorProvidesStructuredConstructionFailure() {
        let failure = StubError.requirementMismatch(
            protocolName: "Service",
            requirementIndex: 1,
            expected: "method",
            actual: "getter"
        ).testDoubleFailure

        #expect(failure.phase == .construction)
        #expect(failure.code == .requirementMismatch)
        #expect(
            failure.context.fields == [
                .init(key: "protocolName", value: "Service"),
                .init(key: "requirementIndex", value: "1"),
                .init(key: "expected", value: "method"),
                .init(key: "actual", value: "getter")
            ]
        )
        #expect(
            failure.description
                == "Requirement 1 for 'Service' is `method`, but the supplied "
                + "`Stub.Requirement` describes `getter`. Update that requirement to match "
                + "the protocol declaration."
        )
    }
}

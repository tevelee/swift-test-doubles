import IssueReporting
@_spi(Testing) import TestDoubles
import TestDoublesTesting
import Testing

private protocol ScopedTestDoubleProbe {
    func track(_ value: Int)
}

private protocol ScopedQueuedTestDoubleProbe {
    func nextValue() -> Int
}

private protocol ScopedSuspendedTestDoubleProbe {
    func load() async -> Int
}

private struct ScopedTestDoubleProbeStub: ScopedTestDoubleProbe, ManualStubConformer {
    let stub: ManualStub<Self>

    func track(_ value: Int) {
        stub.call(value)
    }
}

private actor ScopedAsyncInvocationGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func makeScopedTestDoubleStub() throws -> Stub<any ScopedTestDoubleProbe> {
    try Stub<any ScopedTestDoubleProbe>(.method(Int.self, returning: Void.self))
}

private func makeScopedQueuedTestDoubleStub() throws -> Stub<any ScopedQueuedTestDoubleProbe> {
    try Stub<any ScopedQueuedTestDoubleProbe>(.method(returning: Int.self))
}

private func makeScopedSuspendedTestDoubleStub() throws -> Stub<any ScopedSuspendedTestDoubleProbe> {
    try Stub<any ScopedSuspendedTestDoubleProbe>(
        .method(returning: Int.self, isAsync: true)
    )
}

@Suite struct SwiftTestingIntegrationTests {
    @Test(.testDoubles)
    func testDoubleScopeAllowsUsedRegistrations() throws {
        let stub = try makeScopedTestDoubleStub()
        stub.when { $0.track(42) }.thenDoNothing()

        stub().track(42)
    }

    @Test(.strictTestDoubles)
    func strictTestDoubleScopeAllowsVerifiedInteractions() throws {
        let stub = try makeScopedTestDoubleStub()
        stub.when { $0.track(42) }.thenDoNothing()

        stub().track(42)
        stub.verify { $0.track(42) }
    }

    @Test func scopeReportsUnusedRegistrations() throws {
        let session = TestDoubleSession()
        try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedTestDoubleStub()
            stub.when { $0.track(42) }.thenDoNothing()
        }

        #expect(
            session.diagnostics(
                checkingUnusedRegistrations: true,
                checkingUnverifiedInteractions: false
            ).contains { $0.contains("Unused stub registrations") })
    }

    @Test func strictScopeReportsUnverifiedInteractions() throws {
        let session = TestDoubleSession()
        try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedTestDoubleStub()
            stub.when { $0.track(42) }.thenDoNothing()
            stub().track(42)
        }

        #expect(
            session.diagnostics(
                checkingUnusedRegistrations: true,
                checkingUnverifiedInteractions: true
            ).contains { $0.contains("Expected no more interactions") })
    }

    @Test func strictnessIncludesLifecycleChecks() {
        #expect(TestDoubleStrictness.strict.contains(.noUnconsumedBehaviorQueues))
        #expect(TestDoubleStrictness.strict.contains(.noPendingSuspensions))
        #expect(TestDoubleStrictness.strict.contains(.noPendingCallbackCaptures))
        #expect(TestDoubleStrictness.strict.contains(.noEscapedTestDoubles))
        #expect(TestDoubleStrictness.strict.contains(.noUnfinishedAsyncInvocations))
    }

    @Test(.testDoubles(strictness: []))
    func customStrictnessCanDisableAutomaticChecks() {
        let scope = TestDoubleScope(strictness: .noMoreInteractions)
        #expect(scope.strictness == .noMoreInteractions)
    }

    @Test func scopeReportsUnconsumedFiniteBehaviorQueuesWithDoubleName() throws {
        let session = TestDoubleSession()
        let diagnostics = try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedQueuedTestDoubleStub().named("retry loader")
            _ = stub.when { $0.nextValue() }.thenQueue(1, 2)
            return session.diagnostics(
                checkingUnusedRegistrations: false,
                checkingUnverifiedInteractions: false,
                checkingUnconsumedBehaviorQueues: true
            )
        }

        #expect(
            diagnostics.contains {
                $0.contains("finite behavior queue for test double 'retry loader'")
                    && $0.contains("2 answers remain")
            }
        )
    }

    @Test func scopeReportsParkedSuspensions() async throws {
        let session = TestDoubleSession()
        let diagnostics = try await TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedSuspendedTestDoubleStub().named("feed loader")
            let suspension = await stub.when { await $0.load() }.thenSuspend()
            let task = Task { await stub().load() }
            await suspension.waitForCall()

            let diagnostics = session.diagnostics(
                checkingUnusedRegistrations: false,
                checkingUnverifiedInteractions: false,
                checkingPendingSuspensions: true
            )
            suspension.resume(returning: 42)
            #expect(await task.value == 42)
            return diagnostics
        }

        #expect(
            diagnostics.contains {
                $0.contains("suspended call for test double 'feed loader'")
                    && $0.contains("1 call remains parked")
            }
        )
    }

    @Test func scopeReportsPendingCallbackCaptures() {
        let session = TestDoubleSession()
        let diagnostics = TestDoubleTestingContext.$session.withValue(session) {
            let callbacks = CallbackCapture<Int>().named("completion")
            callbacks.capture { _ in }
            return session.diagnostics(
                checkingUnusedRegistrations: false,
                checkingUnverifiedInteractions: false,
                checkingPendingCallbackCaptures: true
            )
        }

        #expect(
            diagnostics.contains {
                $0.contains("captured callbacks 'completion'")
                    && $0.contains("1 callback remains")
            }
        )
    }

    @Test func failureArtifactsIncludeTimelinesAndChangedFixtureDiffs() throws {
        let session = TestDoubleSession()
        let attachments = try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedQueuedTestDoubleStub().named("price loader")
            let recording = RecordingSession(
                comparingAgainst: InteractionFixture(),
                named: "weather fixture"
            )
            stub.when { $0.nextValue() }
                .thenRecord(as: "temperature", into: recording) { 21 }

            #expect(stub().nextValue() == 21)
            return session.failureAttachments()
        }

        let timeline = try #require(
            attachments.first { $0.name == "price-loader-timeline.txt" }
        )
        #expect(timeline.contents.contains("stubbed requirement_0()"))

        let fixtureDiff = try #require(
            attachments.first { $0.name == "weather-fixture-fixture.diff" }
        )
        #expect(fixtureDiff.contents.hasPrefix("--- expected\n+++ recorded"))
        #expect(fixtureDiff.contents.contains(#""temperature""#))
    }

    @Test func unchangedFixtureDoesNotCreateADiffAttachment() {
        let session = TestDoubleSession()
        let attachments = TestDoubleTestingContext.$session.withValue(session) {
            _ = RecordingSession(
                comparingAgainst: InteractionFixture(),
                named: "empty fixture"
            )
            return session.failureAttachments()
        }

        #expect(attachments.isEmpty)
    }

    @Test func scopeReportsEscapedGeneratedProtocolValues() throws {
        let session = TestDoubleSession()
        var escapedValue: (any ScopedQueuedTestDoubleProbe)?
        try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedQueuedTestDoubleStub().named("escaped loader")
            escapedValue = stub()
        }
        let diagnostics = session.diagnostics(
            checkingUnusedRegistrations: false,
            checkingUnverifiedInteractions: false,
            checkingEscapedTestDoubles: true
        )

        #expect(
            diagnostics.contains {
                $0.contains("Test double 'escaped loader' outlived its test scope")
            }
        )
        withExtendedLifetime(escapedValue) {}
    }

    @Test func scopeReportsEscapedManualControllersAndInjectedClosures() {
        let session = TestDoubleSession()
        var escapedFunction: ((Int) -> Void)?
        TestDoubleTestingContext.$session.withValue(session) {
            let stub = ManualStub<ScopedTestDoubleProbeStub>().named("event sink")
            let value = stub()
            escapedFunction = { value.track($0) }
        }
        let diagnostics = session.diagnostics(
            checkingUnusedRegistrations: false,
            checkingUnverifiedInteractions: false,
            checkingEscapedTestDoubles: true
        )

        #expect(
            diagnostics.contains {
                $0.contains("Test double 'event sink' outlived its test scope")
            }
        )
        withExtendedLifetime(escapedFunction) {}
    }

    @Test func scopeAcceptsDoublesReleasedBeforeTeardown() throws {
        let session = TestDoubleSession()
        try TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedQueuedTestDoubleStub()
            withExtendedLifetime(stub()) {}
        }

        #expect(
            session.diagnostics(
                checkingUnusedRegistrations: false,
                checkingUnverifiedInteractions: false,
                checkingEscapedTestDoubles: true
            ).isEmpty
        )
    }

    @Test func scopeReportsAsyncInvocationsStillRunningAtTeardown() async throws {
        let session = TestDoubleSession()
        let gate = ScopedAsyncInvocationGate()
        try await TestDoubleTestingContext.$session.withValue(session) {
            let stub = try makeScopedSuspendedTestDoubleStub().named("background loader")
            await stub.when { await $0.load() }.then { () async -> Int in
                await gate.suspend()
                return 42
            }
            let task = Task { await stub().load() }
            await gate.waitUntilStarted()

            let diagnostics = session.diagnostics(
                checkingUnusedRegistrations: false,
                checkingUnverifiedInteractions: false,
                checkingUnfinishedAsyncInvocations: true
            )
            #expect(
                diagnostics.contains {
                    $0.contains("Test double 'background loader'")
                        && $0.contains("1 invocation still running")
                        && $0.contains("requirement_0")
                }
            )

            await gate.release()
            #expect(await task.value == 42)
            #expect(
                session.diagnostics(
                    checkingUnusedRegistrations: false,
                    checkingUnverifiedInteractions: false,
                    checkingUnfinishedAsyncInvocations: true
                ).isEmpty
            )
        }
    }
}

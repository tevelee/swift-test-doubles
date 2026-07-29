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
}

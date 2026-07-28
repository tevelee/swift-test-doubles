import IssueReporting
@_spi(Testing) import TestDoubles
import TestDoublesTesting
import Testing

private protocol ScopedTestDoubleProbe {
    func track(_ value: Int)
}

private func makeScopedTestDoubleStub() throws -> Stub<any ScopedTestDoubleProbe> {
    try Stub<any ScopedTestDoubleProbe>(.method(Int.self, returning: Void.self))
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
}

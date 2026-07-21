import IssueReporting
import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol UnreachableProbeFlags: Sendable {
    func isEnabled(_ flag: String, for userID: Int) -> Bool
    func reset()
}

struct RealUnreachableProbeFlags: UnreachableProbeFlags {
    func isEnabled(_ flag: String, for userID: Int) -> Bool { false }
    func reset() {}
}

@Suite struct UnreachableRegistrationTests {
    @Test func catchAllBeforeSpecificReportsAtTheWhenSite() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        stub.when { $0.isEnabled(any(), for: any()) }.thenReturn(false)

        expectReportsIssue {
            stub.when { $0.isEnabled(equal("new_checkout"), for: equal(7)) }.thenReturn(true)
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }
    }

    @Test func specificBeforeBroadDoesNotReport() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        // Correct ordering: specific first, broad fallback last. No shadow.
        stub.when { $0.isEnabled(equal("new_checkout"), for: equal(7)) }.thenReturn(true)
        stub.when { $0.isEnabled(equal("new_checkout"), for: any()) }.thenReturn(true)
        stub.when { $0.isEnabled(any(), for: any()) }.thenReturn(false)
    }

    @Test func perArgumentSupersetIsDetected() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        // Earlier accepts any flag for user 7; later only flag "x" for user 7,
        // a strict subset, so later can never match.
        stub.when { $0.isEnabled(any(), for: equal(7)) }.thenReturn(true)

        expectReportsIssue {
            stub.when { $0.isEnabled(equal("x"), for: equal(7)) }.thenReturn(true)
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }
    }

    @Test func partialOverlapWithoutSupersetDoesNotReport() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        // Earlier pins user 7; later pins user 9. Neither is a superset of the
        // other, so both are reachable.
        stub.when { $0.isEnabled(any(), for: equal(7)) }.thenReturn(true)
        stub.when { $0.isEnabled(any(), for: equal(9)) }.thenReturn(true)
    }

    @Test func duplicateRegistrationIsUnreachable() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        stub.when { $0.isEnabled(equal("x"), for: equal(7)) }.thenReturn(true)

        expectReportsIssue {
            stub.when { $0.isEnabled(equal("x"), for: equal(7)) }.thenReturn(false)
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }
    }

    @Test func secondRegistrationForAZeroArgRequirementIsUnreachable() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        stub.when { $0.reset() }.thenDoNothing()

        expectReportsIssue {
            stub.when { $0.reset() }.thenDoNothing()
        } matching: {
            $0.description.contains("Unreachable stub registration")
        }
    }

    @Test func opaquePredicatesAreNotFalselyFlagged() throws {
        let stub = try Stub<any UnreachableProbeFlags>()
        // Two different predicates the library cannot prove overlap; it must
        // not guess a shadow relationship.
        stub.when {
            $0.isEnabled(matching(description: "long", where: { $0.count > 3 }), for: any())
        }.thenReturn(true)
        stub.when {
            $0.isEnabled(matching(description: "short", where: { $0.count <= 3 }), for: any())
        }.thenReturn(false)
    }
}

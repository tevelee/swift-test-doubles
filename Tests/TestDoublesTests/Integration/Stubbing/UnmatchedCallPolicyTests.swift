import IssueReporting
import TestDoubles
import Testing

// Internal, not private: the conformers double as automatic-discovery
// fixtures, whose conformance records must stay reachable in release builds.
protocol UnmatchedPolicyService {
    func track(event: String)
    func lookUp(id: Int) -> String
    func session() -> any UnmatchedPolicySession
}

protocol UnmatchedPolicySession {
    func close()
}

struct LiveUnmatchedPolicyService: UnmatchedPolicyService {
    func track(event: String) {}
    func lookUp(id: Int) -> String { "live-\(id)" }
    func session() -> any UnmatchedPolicySession { LiveUnmatchedPolicySession() }
}

struct LiveUnmatchedPolicySession: UnmatchedPolicySession {
    func close() {}
}

private protocol ManualUnmatchedPolicyService {
    func track(event: String)
    func lookUp(id: Int) -> String
}

private struct ManualUnmatchedPolicyServiceStub: ManualUnmatchedPolicyService,
    ManualStubConformer
{
    let stub: ManualStub<Self>

    func track(event: String) { stub.track(event: event) }
    func lookUp(id: Int) -> String { stub.lookUp(id: id) }
}

/// A result type with no generally available initializer, so recovery cannot
/// synthesize a placeholder for it.
final class UnsynthesizableResult {
    init(required: Int) { _ = required }
}

protocol UnsynthesizableResultService {
    func build() -> UnsynthesizableResult
}

struct UnsynthesizableResultServiceStub: UnsynthesizableResultService,
    ManualStubConformer
{
    let stub: ManualStub<Self>

    func build() -> UnsynthesizableResult { stub.build() }
}

@Suite struct UnmatchedCallPolicyTests {
    @Test func `a void requirement recovers and reports one issue`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        ).onUnmatchedCall(.reportIssue)
        let service: any UnmatchedPolicyService = stub()

        expectReportsIssue {
            service.track(event: "purchase")
        } matching: { issue in
            issue.description.contains("No stub configured")
                && issue.description.contains("track")
        }

        #expect(stub.history.callCount == 1)
        stub.verify { $0.track(event: Match.equal("purchase")) }
    }

    @Test func `an unmatched argument recovers without losing the run`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        ).onUnmatchedCall(.reportIssue)
        stub.when { $0.lookUp(id: Match.equal(1)) }.thenReturn("one")
        let service: any UnmatchedPolicyService = stub()

        #expect(service.lookUp(id: 1) == "one")

        expectReportsIssue {
            _ = service.lookUp(id: 2)
        } matching: { issue in
            issue.description.contains("No matching stub")
                && issue.description.contains("arg0 rejected")
        }

        stub.verify(2 ... 2) { $0.lookUp(id: Match.any()) }
    }

    @Test func `a supplied recovery value answers the call`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        ).onUnmatchedCall(
            .reportIssue(recoveringWith: { type in
                type == String.self ? "recovered" : nil
            })
        )
        let service: any UnmatchedPolicyService = stub()

        var value = ""
        expectReportsIssue {
            value = service.lookUp(id: 7)
        } matching: { _ in
            true
        }
        #expect(value == "recovered")
    }

    @Test func `a wrongly typed recovery value falls back to synthesis`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        ).onUnmatchedCall(.reportIssue(recoveringWith: { _ in 42 }))
        let service: any UnmatchedPolicyService = stub()

        var value = "unset"
        expectReportsIssue {
            value = service.lookUp(id: 7)
        } matching: { _ in
            true
        }
        #expect(value == "")
    }

    @Test func `a protocol result recovers as a fail-on-use existential`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        ).onUnmatchedCall(.reportIssue)
        let service: any UnmatchedPolicyService = stub()

        expectReportsIssue {
            _ = service.session()
        } matching: { _ in
            true
        }

        #expect(stub.history.callCount == 1)
    }

    @Test func `the policy applies to manual stubs`() {
        let stub = ManualStub<ManualUnmatchedPolicyServiceStub>()
            .onUnmatchedCall(.reportIssue)
        let service: any ManualUnmatchedPolicyService = stub()

        expectReportsIssue {
            service.track(event: "manual")
        } matching: { _ in
            true
        }

        stub.verify { $0.track(event: Match.equal("manual")) }
    }

    @Test func `the policy applies to closure doubles`() {
        let double = ClosureDouble<Int, String>().onUnmatchedCall(.reportIssue)
        let function = double.function

        var value = "unset"
        expectReportsIssue {
            value = function(1)
        } matching: { _ in
            true
        }
        #expect(value == "")
        double.verify(matching: { $0 == 1 }, describedBy: "one")
    }

    @Test func `trapping stays the default`() throws {
        let stub = try Stub<any UnmatchedPolicyService>(
            discoveringFrom: LiveUnmatchedPolicyService()
        )
        #expect(stub.history.callCount == 0)
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct UnmatchedCallPolicyExitTests {
        @Test func `an unconfigured call still ends the process by default`() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = ManualStub<ManualUnmatchedPolicyServiceStub>()
                let service: any ManualUnmatchedPolicyService = stub()
                service.track(event: "boom")
            }
            let output = try requireStandardErrorDiagnostic(from: result)
            #expect(output.contains("No stub configured"))
        }

        @Test func `a recovered protocol result fails on use`() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any UnmatchedPolicyService>(
                    discoveringFrom: LiveUnmatchedPolicyService()
                ).onUnmatchedCall(.reportIssue)
                let service: any UnmatchedPolicyService = stub()
                service.session().close()
            }
            let output = try requireStandardErrorDiagnostic(from: result)
            #expect(output.contains("Dummy<TestDoublesTests.UnmatchedPolicySession>"))
            #expect(
                output.contains(
                    "A dummy may only be passed to code paths that do not use it"
                )
            )
        }

        @Test func `a result that cannot be synthesized still traps`() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = ManualStub<UnsynthesizableResultServiceStub>()
                    .onUnmatchedCall(.reportIssue)
                let service: any UnsynthesizableResultService = stub()
                _ = service.build()
            }
            let output = try requireStandardErrorDiagnostic(from: result)
            #expect(output.contains("No stub configured"))
            #expect(output.contains("has no value to return"))
        }
    }
#endif

import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol InvocationAccessAnalytics {
    func track(event: String, value: Int)
    func load(url: String) async throws -> String
}

struct RealInvocationAccessAnalytics: InvocationAccessAnalytics {
    func track(event: String, value: Int) {}
    func load(url: String) async throws -> String { url }
}

private protocol ManualInvocationAccessService {
    func track(event: String, value: Int)
}

private struct ManualInvocationAccessServiceStub: ManualInvocationAccessService, StubConformer {
    let stub: ManualStub<Self>

    func track(event: String, value: Int) { stub.track(event: event, value: value) }
}

@Suite struct TypedInvocationAccessTests {
    @Test func manualStubReturnsTypedArgumentTuples() {
        let stub = ManualStub<ManualInvocationAccessServiceStub>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

        let service: any ManualInvocationAccessService = stub()
        service.track(event: "add_to_cart", value: 30)
        service.track(event: "purchase", value: 42)

        let events: [(String, Int)] = stub.invocations {
            $0.track(event: any(), value: any())
        }
        #expect(events.count == 2)
        #expect(events[0] == ("add_to_cart", 30))
        #expect(events[1] == ("purchase", 42))
    }

    @Test func returnsTypedArgumentTuplesInCallOrder() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        let events: [(String, Int)] = stub.invocations {
            $0.track(event: any(), value: any())
        }
        #expect(events.count == 2)
        #expect(events[0] == ("add_to_cart", 30))
        #expect(events[1] == ("purchase", 42))
    }

    @Test func bindsALeadingPrefixOfArguments() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        let names: [String] = stub.invocations {
            $0.track(event: any(), value: any())
        }
        #expect(names == ["add_to_cart", "purchase"])
    }

    @Test func matchersFilterWhichInvocationsAreIncluded() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "error", value: 1)
        analytics.track(event: "purchase", value: 42)

        let large: [(String, Int)] = stub.invocations {
            $0.track(event: any(), value: greaterThan(10))
        }
        #expect(large.map(\.0) == ["add_to_cart", "purchase"])
    }

    @Test func readsAsyncRequirementInvocations() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        await stub.when { try await $0.load(url: any()) }.thenReturn("data")

        let analytics: any InvocationAccessAnalytics = stub()
        _ = try await analytics.load(url: "https://one.example")
        _ = try await analytics.load(url: "https://two.example")

        let urls: [String] = await stub.invocations {
            try await $0.load(url: any())
        }
        #expect(urls == ["https://one.example", "https://two.example"])
    }

    @Test func returnsEmptyWhenNothingMatched() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)

        let errors: [(String, Int)] = stub.invocations {
            $0.track(event: equal("error"), value: any())
        }
        #expect(errors.isEmpty)
    }

    @Test func readingDoesNotConsumeConfiguredBehavior() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        await stub.when { try await $0.load(url: any()) }
            .thenReturn("first")
            .thenReturn("second")

        let analytics: any InvocationAccessAnalytics = stub()
        #expect(try await analytics.load(url: "a") == "first")

        let urls: [String] = await stub.invocations { try await $0.load(url: any()) }
        #expect(urls == ["a"])

        // The read must not have advanced the behavior chain.
        #expect(try await analytics.load(url: "b") == "second")
    }
}

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

    @Test func streamYieldsFutureTypedArgumentsInOrder() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()

        analytics.track(event: "before", value: 0)
        let stream: InvocationStream<(String, Int)> = stub.invocationStream {
            $0.track(event: any(), value: any())
        }
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        var iterator = stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        #expect(first.0 == "add_to_cart")
        #expect(first.1 == 30)
        #expect(second.0 == "purchase")
        #expect(second.1 == 42)

        // Streaming is observational, just like the existing invocation query.
        stub.verify(.exactly(3)) { $0.track(event: any(), value: any()) }
    }

    @Test func streamFiltersFutureCallsWithMatchers() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()
        let stream: InvocationStream<String> = stub.invocationStream {
            $0.track(event: any(), value: greaterThan(10))
        }

        analytics.track(event: "ignored", value: 1)
        analytics.track(event: "kept", value: 30)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "kept")
    }

    @Test func streamSupportsAsyncRequirements() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        await stub.when { try await $0.load(url: any()) }.thenReturn("data")
        let analytics: any InvocationAccessAnalytics = stub()
        let stream: InvocationStream<String> = await stub.invocationStream {
            try await $0.load(url: any())
        }

        _ = try await analytics.load(url: "https://one.example")
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "https://one.example")
    }

    @Test func manualStubStreamsFutureCalls() async throws {
        let stub = ManualStub<ManualInvocationAccessServiceStub>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()
        let service: any ManualInvocationAccessService = stub()
        let stream: InvocationStream<(String, Int)> = stub.invocationStream {
            $0.track(event: any(), value: any())
        }

        service.track(event: "purchase", value: 42)
        var iterator = stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.0 == "purchase")
        #expect(event.1 == 42)
    }

    @Test func streamCancellationFinishesTheAwaitingIterator() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()
        let stream: InvocationStream<(String, Int)> = stub.invocationStream {
            $0.track(event: any(), value: any())
        }

        let next = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        var isWaiting = false
        for _ in 0 ..< 100 {
            if stub.recorder.withLockedPolicy({
                $0.invocationLedger.pendingWaiterCount(for: 0)
            }) == 1 {
                isWaiting = true
                break
            }
            await Task.yield()
        }
        #expect(isWaiting)
        next.cancel()

        #expect(await next.value == nil)
        #expect(
            stub.recorder.withLockedPolicy {
                $0.invocationLedger.pendingWaiterCount(for: 0)
            } == 0)
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

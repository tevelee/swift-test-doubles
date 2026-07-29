import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol InvocationAccessAnalytics: Sendable {
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
    @Test func callPatternComposesBehaviorHistoryVerificationAndStreaming() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let pattern = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        pattern.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()

        #expect(pattern.wasCalled == false)
        #expect(pattern.callCount == 0)

        analytics.track(event: "before", value: 1)
        #expect(pattern.wasCalled)
        #expect(pattern.callCount == 1)
        let history: [(String, Int)] = pattern.arguments()
        #expect(history.count == 1)
        #expect(history[0] == ("before", 1))

        let stream: InvocationStream<(String, Int)> = pattern.stream()
        analytics.track(event: "after", value: 2)
        var iterator = stream.makeAsyncIterator()
        let streamed = try #require(await iterator.next())
        #expect(streamed == ("after", 2))

        pattern.verify(.exactly(2))
    }

    @Test func callPatternSupportsEventualVerification() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let pattern = stub.onCall {
            $0.track(event: Match.equal("late"), value: Match.any())
        }
        pattern.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()

        let invocation = Task {
            try await Task.sleep(for: .milliseconds(10))
            analytics.track(event: "late", value: 42)
        }
        await pattern.verify(within: .seconds(1))
        try await invocation.value
    }

    @Test func manualStubReturnsTypedArgumentTuples() {
        let stub = ManualStub<ManualInvocationAccessServiceStub>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()

        let service: any ManualInvocationAccessService = stub()
        service.track(event: "add_to_cart", value: 30)
        service.track(event: "purchase", value: 42)

        let events: [(String, Int)] = allEvents.arguments()
        #expect(events.count == 2)
        #expect(events[0] == ("add_to_cart", 30))
        #expect(events[1] == ("purchase", 42))
    }

    @Test func returnsTypedArgumentTuplesInCallOrder() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        let events: [(String, Int)] = allEvents.arguments()
        #expect(events.count == 2)
        #expect(events[0] == ("add_to_cart", 30))
        #expect(events[1] == ("purchase", 42))
    }

    @Test func bindsALeadingPrefixOfArguments() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        let names: [String] = allEvents.arguments()
        #expect(names == ["add_to_cart", "purchase"])
    }

    @Test func matchersFilterWhichInvocationsAreIncluded() throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.onCall { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "error", value: 1)
        analytics.track(event: "purchase", value: 42)

        let largeEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.greaterThan(10))
        }
        let large: [(String, Int)] = largeEvents.arguments()
        #expect(large.map(\.0) == ["add_to_cart", "purchase"])
    }

    @Test func readsAsyncRequirementInvocations() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let loads = await stub.onCall { try await $0.load(url: Match.any()) }
        loads.thenReturn("data")

        let analytics: any InvocationAccessAnalytics = stub()
        _ = try await analytics.load(url: "https://one.example")
        _ = try await analytics.load(url: "https://two.example")

        let urls: [String] = loads.arguments()
        #expect(urls == ["https://one.example", "https://two.example"])
    }

    @Test func streamYieldsFutureTypedArgumentsInOrder() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()

        analytics.track(event: "before", value: 0)
        let stream: InvocationStream<(String, Int)> = allEvents.stream()
        analytics.track(event: "add_to_cart", value: 30)
        analytics.track(event: "purchase", value: 42)

        var iterator = stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        #expect(first.0 == "add_to_cart")
        #expect(first.1 == 30)
        #expect(second.0 == "purchase")
        #expect(second.1 == 42)

        // Streaming is observational, just like the existing argument query.
        allEvents.verify(.exactly(3))
    }

    @Test func streamFiltersFutureCallsWithMatchers() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        stub.onCall { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()
        let analytics: any InvocationAccessAnalytics = stub()
        let largeEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.greaterThan(10))
        }
        let stream: InvocationStream<String> = largeEvents.stream()

        analytics.track(event: "ignored", value: 1)
        analytics.track(event: "kept", value: 30)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "kept")
    }

    @Test func streamSupportsAsyncRequirements() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let loads = await stub.onCall { try await $0.load(url: Match.any()) }
        loads.thenReturn("data")
        let analytics: any InvocationAccessAnalytics = stub()
        let stream: InvocationStream<String> = loads.stream()

        _ = try await analytics.load(url: "https://one.example")
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "https://one.example")
    }

    @Test func manualStubStreamsFutureCalls() async throws {
        let stub = ManualStub<ManualInvocationAccessServiceStub>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()
        let service: any ManualInvocationAccessService = stub()
        let stream: InvocationStream<(String, Int)> = allEvents.stream()

        service.track(event: "purchase", value: 42)
        var iterator = stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.0 == "purchase")
        #expect(event.1 == 42)
    }

    @Test func streamCancellationFinishesTheAwaitingIterator() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let allEvents = stub.onCall {
            $0.track(event: Match.any(), value: Match.any())
        }
        allEvents.thenDoNothing()
        let stream: InvocationStream<(String, Int)> = allEvents.stream()

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
        stub.onCall { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()

        let analytics: any InvocationAccessAnalytics = stub()
        analytics.track(event: "add_to_cart", value: 30)

        let errorEvents = stub.onCall {
            $0.track(event: Match.equal("error"), value: Match.any())
        }
        let errors: [(String, Int)] = errorEvents.arguments()
        #expect(errors.isEmpty)
    }

    @Test func readingDoesNotConsumeConfiguredBehavior() async throws {
        let stub = try Stub<any InvocationAccessAnalytics>()
        let loads = await stub.onCall { try await $0.load(url: Match.any()) }
        loads
            .thenReturn("first")
            .thenReturn("second")

        let analytics: any InvocationAccessAnalytics = stub()
        #expect(try await analytics.load(url: "a") == "first")

        let urls: [String] = loads.arguments()
        #expect(urls == ["a"])

        // The read must not have advanced the behavior chain.
        #expect(try await analytics.load(url: "b") == "second")
    }
}

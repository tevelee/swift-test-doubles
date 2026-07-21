import Testing
@testable import TestDoubles
import TestDoublesFixtures

private enum DelayedTestError: Error, Equatable {
    case transient
}

@Suite struct DelayedBehaviorTests {
    @Test func delayedReturnDeliversAfterTheDelay() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }
            .thenReturn("slow-data", after: .milliseconds(50))

        let loader: any AsyncDataLoader = stub()
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await loader.load(url: "https://example.com")
        let elapsed = clock.now - start

        #expect(value == "slow-data")
        #expect(elapsed >= .milliseconds(50))
    }

    @Test func delayedThrowDeliversAfterTheDelay() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }
            .thenThrow(DelayedTestError.transient, after: .milliseconds(50))

        let loader: any AsyncDataLoader = stub()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: DelayedTestError.transient) {
            try await loader.load(url: "https://example.com")
        }
        #expect(clock.now - start >= .milliseconds(50))
    }

    @Test func delayedBehaviorsParticipateInChains() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }
            .thenThrow(DelayedTestError.transient, after: .milliseconds(20))
            .thenReturn("recovered")

        let loader: any AsyncDataLoader = stub()
        await #expect(throws: DelayedTestError.transient) {
            try await loader.load(url: "first")
        }
        #expect(try await loader.load(url: "second") == "recovered")
    }

    @Test func delayedReturnRepeatsForItsConfiguredCount() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }
            .thenReturn("slow", after: .milliseconds(10), times: 2)
            .thenReturn("fast")

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "1") == "slow")
        #expect(try await loader.load(url: "2") == "slow")
        #expect(try await loader.load(url: "3") == "fast")
    }

    @Test func delayedCompletionOnNonThrowingVoidRequirement() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { await $0.prefetch(urls: any()) }
            .thenDoNothing(after: .milliseconds(50))

        let loader: any AsyncDataLoader = stub()
        let clock = ContinuousClock()
        let start = clock.now
        await loader.prefetch(urls: ["one"])
        #expect(clock.now - start >= .milliseconds(50))
    }

    @Test func cancellationCutsAThrowingDelayShort() async throws {
        let stub = try Stub<any AsyncDataLoader & Sendable>()
        await stub.when { try await $0.load(url: any()) }
            .thenReturn("never-delivered", after: .seconds(60))

        let loader: any AsyncDataLoader & Sendable = stub()
        let task = Task {
            try await loader.load(url: "cancelled")
        }

        await stub.verify(1..., within: .seconds(60)) {
            try await $0.load(url: equal("cancelled"))
        }

        let clock = ContinuousClock()
        let cancellationStart = clock.now
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(clock.now - cancellationStart < .seconds(30))
    }
}

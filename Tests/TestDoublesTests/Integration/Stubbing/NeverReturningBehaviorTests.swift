import Testing
@testable import TestDoubles
import TestDoublesFixtures

private enum NeverReturnTestError: Error, Equatable {
    case transient
}

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol NeverReturningWedgedService: Sendable {
    func fetch(id: Int) async throws -> String
}

struct RealNeverReturningWedgedService: NeverReturningWedgedService {
    func fetch(id: Int) async throws -> String { "\(id)" }
}

private actor CompletionFlag {
    private(set) var isSet = false
    func set() { isSet = true }
}

@Suite struct NeverReturningBehaviorTests {
    @Test func neverReturnKeepsTheCallerSuspended() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }.thenNeverReturn()

        let completed = CompletionFlag()
        let task = Task {
            let loader: any AsyncDataLoader = stub()
            _ = try? await loader.load(url: "wedged")
            await completed.set()
        }

        try await ContinuousClock().sleep(for: .milliseconds(100))
        #expect(await completed.isSet == false)

        // A parked call must not complete on cancellation either; reacting
        // to cancellation is thenAwaitCancellation's contract.
        task.cancel()
        try await ContinuousClock().sleep(for: .milliseconds(50))
        #expect(await completed.isSet == false)
    }

    @Test func neverReturnParticipatesInChains() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }
            .thenThrow(NeverReturnTestError.transient)
            .thenNeverReturn()

        let loader: any AsyncDataLoader = stub()
        await #expect(throws: NeverReturnTestError.transient) {
            try await loader.load(url: "first")
        }

        let completed = CompletionFlag()
        Task {
            let parked: any AsyncDataLoader = stub()
            _ = try? await parked.load(url: "second")
            await completed.set()
        }
        try await ContinuousClock().sleep(for: .milliseconds(100))
        #expect(await completed.isSet == false)
    }

    @Test func parkedCallsRemainObservableThroughVerification() async throws {
        let stub = try Stub<any NeverReturningWedgedService>()
        await stub.when { try await $0.fetch(id: any()) }.thenNeverReturn()

        let service: any NeverReturningWedgedService = stub()
        Task {
            _ = try? await service.fetch(id: 7)
        }

        // The invocation is recorded before the call parks, so eventual
        // verification observes it even though it never completes.
        await stub.verify(1..., within: .seconds(1)) {
            try await $0.fetch(id: equal(7))
        }
    }
}

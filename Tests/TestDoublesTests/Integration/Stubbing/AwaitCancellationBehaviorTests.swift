import Testing
@testable import TestDoubles

private enum AwaitCancellationTestError: Error, Equatable {
    case aborted
}

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol AwaitCancellationService: Sendable {
    func fetch(id: Int) async throws -> String
    func run() async
    func poll() async -> Int
}

struct RealAwaitCancellationService: AwaitCancellationService {
    func fetch(id: Int) async throws -> String { "\(id)" }
    func run() async {}
    func poll() async -> Int { 0 }
}

private actor CompletionFlag {
    private(set) var isSet = false
    func set() { isSet = true }
}

@Suite struct AwaitCancellationBehaviorTests {
    @Test func bareFormThrowsCancellationErrorOnAThrowingRequirement() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { try await $0.fetch(id: any()) }.thenAwaitCancellation()

        let service: any AwaitCancellationService = stub()
        let task = Task {
            try await service.fetch(id: 1)
        }
        await stub.verify(1..., within: .seconds(1)) { try await $0.fetch(id: any()) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func returningFormCompletesWithTheValueAfterCancellation() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { await $0.poll() }.thenAwaitCancellation(returning: -1)

        let service: any AwaitCancellationService = stub()
        let task = Task {
            await service.poll()
        }
        await stub.verify(1..., within: .seconds(1)) { await $0.poll() }
        task.cancel()

        #expect(await task.value == -1)
    }

    @Test func throwingFormThrowsTheConfiguredErrorAfterCancellation() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { try await $0.fetch(id: any()) }
            .thenAwaitCancellation(throwing: AwaitCancellationTestError.aborted)

        let service: any AwaitCancellationService = stub()
        let task = Task {
            try await service.fetch(id: 2)
        }
        await stub.verify(1..., within: .seconds(1)) { try await $0.fetch(id: any()) }
        task.cancel()

        await #expect(throws: AwaitCancellationTestError.aborted) {
            try await task.value
        }
    }

    @Test func bareFormReturnsOnANonThrowingVoidRequirement() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { await $0.run() }.thenAwaitCancellation()

        let service: any AwaitCancellationService = stub()
        let completed = CompletionFlag()
        let task = Task {
            await service.run()
            await completed.set()
        }
        await stub.verify(1..., within: .seconds(1)) { await $0.run() }
        #expect(await completed.isSet == false)

        task.cancel()
        await task.value
        #expect(await completed.isSet)
    }

    @Test func awaitCancellationTerminatesAChain() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { try await $0.fetch(id: any()) }
            .thenReturn("ok")
            .thenAwaitCancellation()

        let service: any AwaitCancellationService = stub()
        #expect(try await service.fetch(id: 1) == "ok")

        let task = Task {
            try await service.fetch(id: 2)
        }
        await stub.verify(2..., within: .seconds(1)) { try await $0.fetch(id: any()) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func alreadyCancelledTaskCompletesImmediately() async throws {
        let stub = try Stub<any AwaitCancellationService>()
        await stub.when { await $0.poll() }.thenAwaitCancellation(returning: -1)

        let service: any AwaitCancellationService = stub()
        let task = Task {
            await service.poll()
        }
        task.cancel()

        #expect(await task.value == -1)
    }
}

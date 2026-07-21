import Testing
@testable import TestDoubles

private enum SuspensionTestError: Error, Equatable {
    case backendDown
}

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol SuspensionProbeService: Sendable {
    func fetch(id: Int) async throws -> String
    func warmUp() async
}

struct RealSuspensionProbeService: SuspensionProbeService {
    func fetch(id: Int) async throws -> String { "\(id)" }
    func warmUp() async {}
}

private actor CompletionFlag {
    private(set) var isSet = false
    func set() { isSet = true }
}

@Suite struct SuspensionBehaviorTests {
    @Test func resumeReturningCompletesAParkedCall() async throws {
        let stub = try Stub<any SuspensionProbeService>()
        let suspension = await stub.when { try await $0.fetch(id: any()) }.thenSuspend()

        let service: any SuspensionProbeService = stub()
        let completed = CompletionFlag()
        let task = Task {
            let value = try await service.fetch(id: 1)
            await completed.set()
            return value
        }

        await suspension.waitForCall()
        // The call has arrived and is parked; nothing has completed yet.
        #expect(await completed.isSet == false)

        suspension.resume(returning: "late")
        #expect(try await task.value == "late")
        #expect(await completed.isSet)
    }

    @Test func resumeThrowingCompletesAParkedCall() async throws {
        let stub = try Stub<any SuspensionProbeService>()
        let suspension = await stub.when { try await $0.fetch(id: any()) }.thenSuspend()

        let service: any SuspensionProbeService = stub()
        let task = Task {
            try await service.fetch(id: 2)
        }

        await suspension.waitForCall()
        suspension.resume(throwing: SuspensionTestError.backendDown)

        await #expect(throws: SuspensionTestError.backendDown) {
            try await task.value
        }
    }

    @Test func parkedCallsResumeInArrivalOrder() async throws {
        let stub = try Stub<any SuspensionProbeService>()
        let suspension = await stub.when { try await $0.fetch(id: any()) }.thenSuspend()

        let service: any SuspensionProbeService = stub()
        let first = Task { try await service.fetch(id: 1) }
        await suspension.waitForCall()
        let second = Task { try await service.fetch(id: 2) }
        await suspension.waitForCall(count: 2)

        suspension.resume(returning: "first")
        suspension.resume(returning: "second")

        #expect(try await first.value == "first")
        #expect(try await second.value == "second")
    }

    @Test func voidResumeCompletesAParkedVoidCall() async throws {
        let stub = try Stub<any SuspensionProbeService>()
        let suspension = await stub.when { await $0.warmUp() }.thenSuspend()

        let service: any SuspensionProbeService = stub()
        let completed = CompletionFlag()
        let task = Task {
            await service.warmUp()
            await completed.set()
        }

        await suspension.waitForCall()
        #expect(await completed.isSet == false)

        suspension.resume()
        await task.value
        #expect(await completed.isSet)
    }

    @Test func waitForCallReturnsImmediatelyWhenAlreadyParked() async throws {
        let stub = try Stub<any SuspensionProbeService>()
        let suspension = await stub.when { try await $0.fetch(id: any()) }.thenSuspend()

        let service: any SuspensionProbeService = stub()
        let task = Task { try await service.fetch(id: 3) }

        await suspension.waitForCall()
        // A second wait for the same parked count must not deadlock.
        await suspension.waitForCall()

        suspension.resume(returning: "done")
        #expect(try await task.value == "done")
    }
}

import Testing
@testable import TestDoubles

private protocol CancellationInjectionService: Sendable {
    func fetch() async throws -> String
    func poll() async -> Int
}

private struct RealCancellationInjectionService: CancellationInjectionService {
    func fetch() async throws -> String { "real" }
    func poll() async -> Int { 0 }
}

@Suite struct CancellationInjectionBehaviorTests {
    @Test func throwingRequirementCancelsItsCallerAfterTheDelay() async throws {
        _ = RealCancellationInjectionService()
        let clock = ManualStubClock()
        let stub = try Stub<any CancellationInjectionService>()
        let pattern = await stub.when { try await $0.fetch() }
        pattern.thenCancel(after: .seconds(1), using: clock)
        let service: any CancellationInjectionService = stub()

        let task = Task {
            do {
                _ = try await service.fetch()
                return (isCancelled: Task.isCancelled, error: nil as (any Error)?)
            } catch {
                return (isCancelled: Task.isCancelled, error: error)
            }
        }
        await clock.waitForSleepers(atLeast: 1)

        #expect(task.isCancelled == false)
        guard case .pending = pattern.lastOutcome else {
            Issue.record("Expected cancellation injection to remain pending before its delay")
            return
        }

        clock.advance(by: .seconds(1))
        let completion = await task.value
        #expect(completion.isCancelled)
        #expect(completion.error is CancellationError)
        guard case .threw(let error) = pattern.lastOutcome else {
            Issue.record("Expected cancellation injection to record its thrown outcome")
            return
        }
        #expect(error is CancellationError)
    }

    @Test func nonthrowingRequirementReturnsFallbackInACancelledTask() async throws {
        _ = RealCancellationInjectionService()
        let clock = ManualStubClock()
        let stub = try Stub<any CancellationInjectionService>()
        await stub.when { await $0.poll() }
            .thenCancel(after: .milliseconds(250), returning: -1, using: clock)
        let service: any CancellationInjectionService = stub()

        let task = Task {
            let value = await service.poll()
            return (value: value, isCancelled: Task.isCancelled)
        }
        await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(250))

        let completion = await task.value
        #expect(completion.value == -1)
        #expect(completion.isCancelled)
    }

    @Test func asyncClosurePatternSharesCancellationInjection() async {
        let clock = ManualStubClock()
        let closure = AsyncClosureDouble<Int, Int>()
        closure.whenAny()
            .thenCancel(after: .milliseconds(10), returning: -1, using: clock)

        let task = Task {
            let value = await closure(42)
            return (value: value, isCancelled: Task.isCancelled)
        }
        await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))

        let completion = await task.value
        #expect(completion.value == -1)
        #expect(completion.isCancelled)
        #expect(closure.invocations == [42])
    }
}

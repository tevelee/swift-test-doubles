import Dispatch
import Foundation
import Testing
@testable import TestDoubles

@available(iOS 17, macCatalyst 17, tvOS 17, watchOS 10, *)
private final class QueueSerialExecutor: @unchecked Sendable, SerialExecutor {
    private let queue = DispatchQueue(label: "TestDoubles.QueueSerialExecutor")
    private let queueKey = DispatchSpecificKey<Void>()

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    func enqueue(_ job: UnownedJob) {
        let executor = asUnownedSerialExecutor()
        queue.async {
            job.runSynchronously(on: executor)
        }
    }

    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }
}

private protocol CustomExecutorProbe: Sendable {
    func immediate() async -> Int
    func suspending() async -> Int
    func failing() async throws -> Int
}

private enum CustomExecutorError: Error, Equatable {
    case expected
    case wrongExecutor
}

@available(iOS 17, macCatalyst 17, tvOS 17, watchOS 10, *)
private actor CustomExecutorCaller {
    nonisolated let executor: QueueSerialExecutor

    init(executor: QueueSerialExecutor) {
        self.executor = executor
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func makeConfiguredProbe() async throws -> any CustomExecutorProbe {
        let stub = try Stub<any CustomExecutorProbe>(
            .method(returning: Int.self, isAsync: true),
            .method(returning: Int.self, isAsync: true),
            .method(returning: Int.self, isThrowing: true, isAsync: true)
        )
        await stub.when { await $0.immediate() }.thenReturn(1)
        await stub.when { await $0.suspending() }.then {
            () async throws -> Int in
            let enteredOnExecutor = self.executor.isCurrent
            await Task.yield()
            return enteredOnExecutor && self.executor.isCurrent ? 2 : -1
        }
        await stub.when { try await $0.failing() }.then {
            () async throws -> Int in
            guard self.executor.isCurrent else { throw CustomExecutorError.wrongExecutor }
            await Task.yield()
            guard self.executor.isCurrent else { throw CustomExecutorError.wrongExecutor }
            throw CustomExecutorError.expected
        }
        return stub()
    }

    func exercise(_ probe: any CustomExecutorProbe) async {
        #expect(executor.isCurrent)
        #expect(await probe.immediate() == 1)
        #expect(executor.isCurrent)
        #expect(await probe.suspending() == 2)
        #expect(executor.isCurrent)
        await #expect(throws: CustomExecutorError.expected) {
            try await probe.failing()
        }
        #expect(executor.isCurrent)
    }
}

private protocol ConcurrentInvocationProbe: Sendable {
    func synchronous(_ value: Int) -> Int
    func asynchronous(_ value: Int) async -> Int
}

private protocol ConcurrentConstructionProbe: Sendable {
    func reset()
}

private final class BlockedMatcherCompletionGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var blockedMatcherEntered = false
    private var blockedMatcherReleased = false

    func matches(_ value: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        switch value {
            case 1:
                blockedMatcherEntered = true
                condition.broadcast()
                while blockedMatcherReleased == false {
                    condition.wait()
                }
            case 2:
                while blockedMatcherEntered == false {
                    condition.wait()
                }
            default:
                return false
        }
        return true
    }

    func waitUntilBlockedMatcherEntered(within timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while blockedMatcherEntered == false {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    func releaseBlockedMatcher() {
        condition.lock()
        blockedMatcherReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private func requireSendable<T: Sendable>(_: T) {}

@Suite struct ConcurrencyTests {
    @Test func independentStubsCanBeConstructedConcurrently() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    _ = try Stub<any ConcurrentConstructionProbe>(
                        .method(returning: Void.self)
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    @Test
    @available(iOS 17, macCatalyst 17, tvOS 17, watchOS 10, *)
    func asyncDispatchPreservesCustomSerialExecutor() async throws {
        let executor = QueueSerialExecutor()
        let caller = CustomExecutorCaller(executor: executor)
        let probe = try await caller.makeConfiguredProbe()

        await caller.exercise(probe)
        #expect(await probe.suspending() == 2)
        await #expect(throws: CustomExecutorError.expected) {
            try await probe.failing()
        }
    }

    @Test func concurrentSyncAndAsyncCallsRemainIndependent() async throws {
        let stub = try Stub<any ConcurrentInvocationProbe>(
            .method(Int.self, returning: Int.self),
            .method(Int.self, returning: Int.self, isAsync: true)
        )
        let predicateCalls = LockedCounter()
        let syncHandlerCalls = LockedCounter()
        let asyncHandlerCalls = LockedCounter()
        stub.when {
            $0.synchronous(
                matching(
                    description: "nonnegative",
                    where: { value in
                        predicateCalls.increment()
                        return value >= 0
                    })
            )
        }.then { (value: Int) in
            syncHandlerCalls.increment()
            return value * 2
        }
        await stub.when { await $0.asynchronous(any()) }.then {
            (value: Int) async throws -> Int in
            asyncHandlerCalls.increment()
            await Task.yield()
            return value * 3
        }
        let probe: any ConcurrentInvocationProbe = stub()
        let callCount = 250

        requireSendable(ArgumentCaptor<Int>())

        await withTaskGroup(of: Void.self) { group in
            for value in 0 ..< callCount {
                group.addTask {
                    #expect(probe.synchronous(value) == value * 2)
                    #expect(await probe.asynchronous(value) == value * 3)
                }
            }
        }

        #expect(predicateCalls.value >= callCount)
        #expect(syncHandlerCalls.value == callCount)
        #expect(asyncHandlerCalls.value == callCount)
        stub.verify(.exactly(callCount)) {
            $0.synchronous(matching(description: "nonnegative", where: { $0 >= 0 }))
        }
        await stub.verify(.exactly(callCount)) { await $0.asynchronous(any()) }
    }

    @Test(.timeLimit(.minutes(2)))
    func recordingAndQueuedValuesShareMatcherCompletionOrder() async throws {
        let stub = try Stub<any ConcurrentInvocationProbe>(
            .method(Int.self, returning: Int.self),
            .method(Int.self, returning: Int.self, isAsync: true)
        )
        let gate = BlockedMatcherCompletionGate()
        stub.when {
            $0.synchronous(
                matching(description: "gated", where: gate.matches)
            )
        }.thenReturn(10, 20)
        let probe: any ConcurrentInvocationProbe = stub()

        let firstCall = Task.detached(priority: Task.currentPriority) {
            probe.synchronous(1)
        }
        guard gate.waitUntilBlockedMatcherEntered(within: 60) else {
            gate.releaseBlockedMatcher()
            firstCall.cancel()
            _ = await firstCall.value
            Issue.record("The blocking matcher did not start within 60 seconds.")
            return
        }
        let secondCallResult = probe.synchronous(2)
        gate.releaseBlockedMatcher()
        let firstCallResult = await firstCall.value
        let recordedArguments = stub.recorder.verificationMatches(method: 0).compactMap {
            $0.args.first as? Int
        }

        #expect(recordedArguments == [2, 1])
        #expect(secondCallResult == 10)
        #expect(firstCallResult == 20)
    }
}

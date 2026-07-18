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
        return stub(sendability: .unchecked)
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

private final class ReversedMatcherCompletionGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var firstEntered = false
    private var secondCompleted = false

    func matches(_ value: Int) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        switch value {
            case 1:
                firstEntered = true
                condition.broadcast()
                while secondCompleted == false {
                    condition.wait()
                }
            case 2:
                while firstEntered == false {
                    condition.wait()
                }
                secondCompleted = true
                condition.broadcast()
            default:
                return false
        }
        return true
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
        let probe: any ConcurrentInvocationProbe = stub(sendability: .unchecked)
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

    @Test func recordingAndQueuedValuesShareMatcherCompletionOrder() async throws {
        let stub = try Stub<any ConcurrentInvocationProbe>(
            .method(Int.self, returning: Int.self),
            .method(Int.self, returning: Int.self, isAsync: true)
        )
        let gate = ReversedMatcherCompletionGate()
        stub.when {
            $0.synchronous(
                matching(description: "gated", where: gate.matches)
            )
        }.thenReturn(10, 20)
        let probe: any ConcurrentInvocationProbe = stub(sendability: .unchecked)

        let results = await withTaskGroup(
            of: (Int, Int).self,
            returning: [(Int, Int)].self
        ) { group in
            for value in 1 ... 2 {
                group.addTask {
                    (value, probe.synchronous(value))
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let resultsByArgument = Dictionary(uniqueKeysWithValues: results)
        let recordedArguments = stub.recorder.verificationMatches(method: 0).compactMap {
            $0.args.first as? Int
        }

        #expect(recordedArguments == [2, 1])
        #expect(resultsByArgument[2] == 10)
        #expect(resultsByArgument[1] == 20)
    }
}

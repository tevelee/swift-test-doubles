import Dispatch
import Testing
@testable import TestDoubles

@available(iOS 17, *)
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

@available(iOS 17, *)
private actor CustomExecutorCaller {
    nonisolated let executor: QueueSerialExecutor

    init(executor: QueueSerialExecutor) {
        self.executor = executor
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func configure(_ stub: Stub<any CustomExecutorProbe>) async {
        await stub.when { await $0.immediate() }.returns(1)
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

@Suite struct ConcurrencyTests {
    @Test
    @available(iOS 17, *)
    func asyncDispatchPreservesCustomSerialExecutor() async throws {
        let executor = QueueSerialExecutor()
        let caller = CustomExecutorCaller(executor: executor)
        let stub = try Stub<any CustomExecutorProbe>(
            .method(returning: Int.self, isAsync: true),
            .method(returning: Int.self, isAsync: true),
            .method(returning: Int.self, isThrowing: true, isAsync: true)
        )
        await caller.configure(stub)

        await caller.exercise(stub())

        let nonisolatedProbe = stub()
        #expect(await nonisolatedProbe.suspending() == 2)
        await #expect(throws: CustomExecutorError.expected) {
            try await nonisolatedProbe.failing()
        }
    }

    @Test func concurrentSyncAndAsyncCallsRemainIndependent() async throws {
        let stub = try Stub<any ConcurrentInvocationProbe>(
            .method(Int.self, returning: Int.self),
            .method(Int.self, returning: Int.self, isAsync: true)
        )
        stub.when { $0.synchronous(any()) }.then { (value: Int) in value * 2 }
        await stub.when { await $0.asynchronous(any()) }.then {
            (value: Int) async throws -> Int in
            await Task.yield()
            return value * 3
        }
        let probe: any ConcurrentInvocationProbe = stub()
        let callCount = 250

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<callCount {
                group.addTask {
                    #expect(probe.synchronous(value) == value * 2)
                    #expect(await probe.asynchronous(value) == value * 3)
                }
            }
        }

        stub.verify(.exactly(callCount)) { $0.synchronous(any()) }
        await stub.verify(.exactly(callCount)) { await $0.asynchronous(any()) }
    }
}

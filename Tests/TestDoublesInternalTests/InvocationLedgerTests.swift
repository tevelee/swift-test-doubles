import Foundation
import Testing
@testable import TestDoubles

private final class WaitOutcomeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [InvocationLedgerWaitOutcome] = []

    var outcomes: [InvocationLedgerWaitOutcome] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ outcome: InvocationLedgerWaitOutcome) {
        lock.lock()
        storage.append(outcome)
        lock.unlock()
    }
}

@Suite struct InvocationLedgerTests {
    @Test func unrelatedMethodAppendDoesNotDetachOrWakeWaiter() {
        var ledger = InvocationLedger()
        let method = 10
        let initialGeneration = ledger.snapshot(for: method).generation
        let waiterID = ledger.allocateWaiterID()
        let outcomes = WaitOutcomeRecorder()
        let waiter = InvocationLedgerWaiter(resolve: outcomes.append)

        #expect(
            ledger.register(
                waiter,
                id: waiterID,
                after: initialGeneration,
                isCancelled: false
            ) == nil
        )
        #expect(ledger.pendingWaiterCount(for: method) == 1)

        let unrelatedWaiters = ledger.append(method: 11, name: "other()", args: [])

        #expect(unrelatedWaiters.isEmpty)
        #expect(ledger.snapshot(for: method).generation == initialGeneration)
        #expect(ledger.pendingWaiterCount(for: method) == 1)
        #expect(outcomes.outcomes.isEmpty)

        let relatedWaiters = ledger.append(method: method, name: "target()", args: [])
        #expect(relatedWaiters.count == 1)
        #expect(ledger.pendingWaiterCount(for: method) == 0)
        #expect(ledger.removeWaiter(id: waiterID) == nil)

        relatedWaiters.forEach { $0.resume(returning: .changed) }
        #expect(outcomes.outcomes == [.changed])
        #expect(ledger.snapshot(for: method).generation != initialGeneration)
    }

    @Test func simultaneousMethodWaitersRemainIsolated() {
        var ledger = InvocationLedger()
        let firstMethod = 20
        let secondMethod = 21
        let firstOutcomes = WaitOutcomeRecorder()
        let secondOutcomes = WaitOutcomeRecorder()
        let firstWaiterID = ledger.allocateWaiterID()
        let secondWaiterID = ledger.allocateWaiterID()

        #expect(
            ledger.register(
                InvocationLedgerWaiter(resolve: firstOutcomes.append),
                id: firstWaiterID,
                after: ledger.snapshot(for: firstMethod).generation,
                isCancelled: false
            ) == nil
        )
        #expect(
            ledger.register(
                InvocationLedgerWaiter(resolve: secondOutcomes.append),
                id: secondWaiterID,
                after: ledger.snapshot(for: secondMethod).generation,
                isCancelled: false
            ) == nil
        )

        let firstWaiters = ledger.append(method: firstMethod, name: "first()", args: [])
        #expect(firstWaiters.count == 1)
        #expect(ledger.pendingWaiterCount(for: firstMethod) == 0)
        #expect(ledger.pendingWaiterCount(for: secondMethod) == 1)
        firstWaiters.forEach { $0.resume(returning: .changed) }

        #expect(firstOutcomes.outcomes == [.changed])
        #expect(secondOutcomes.outcomes.isEmpty)

        let secondWaiters = ledger.append(method: secondMethod, name: "second()", args: [])
        #expect(secondWaiters.count == 1)
        secondWaiters.forEach { $0.resume(returning: .changed) }

        #expect(firstOutcomes.outcomes == [.changed])
        #expect(secondOutcomes.outcomes == [.changed])
    }

    @Test func clearInvalidatesGenerationsAndDetachesEveryMethodBucket() {
        var ledger = InvocationLedger()
        let firstMethod = 30
        let secondMethod = 31
        let firstGeneration = ledger.snapshot(for: firstMethod).generation
        let secondGeneration = ledger.snapshot(for: secondMethod).generation
        let firstOutcomes = WaitOutcomeRecorder()
        let secondOutcomes = WaitOutcomeRecorder()

        #expect(
            ledger.register(
                InvocationLedgerWaiter(resolve: firstOutcomes.append),
                id: ledger.allocateWaiterID(),
                after: firstGeneration,
                isCancelled: false
            ) == nil
        )
        #expect(
            ledger.register(
                InvocationLedgerWaiter(resolve: secondOutcomes.append),
                id: ledger.allocateWaiterID(),
                after: secondGeneration,
                isCancelled: false
            ) == nil
        )

        let clearedWaiters = ledger.clear()
        #expect(clearedWaiters.count == 2)
        #expect(ledger.pendingWaiterCount(for: firstMethod) == 0)
        #expect(ledger.pendingWaiterCount(for: secondMethod) == 0)
        #expect(ledger.snapshot(for: firstMethod).generation != firstGeneration)
        #expect(ledger.snapshot(for: secondMethod).generation != secondGeneration)

        clearedWaiters.forEach { $0.resume(returning: .changed) }
        #expect(firstOutcomes.outcomes == [.changed])
        #expect(secondOutcomes.outcomes == [.changed])

        let staleOutcome = ledger.register(
            InvocationLedgerWaiter(resolve: { _ in }),
            id: ledger.allocateWaiterID(),
            after: firstGeneration,
            isCancelled: false
        )
        #expect(staleOutcome == .changed)
        #expect(ledger.pendingWaiterCount(for: firstMethod) == 0)
    }
}

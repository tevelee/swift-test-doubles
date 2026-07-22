import Foundation
import IssueReporting
import Testing
@testable import TestDoubles

// Internal, not private: the conformers double as automatic-discovery
// fixtures, whose conformance records must stay reachable in release builds.
protocol CrossOrderGateway: Sendable {
    func charge(amount: Int)
    func settle() async
}

struct RealCrossOrderGateway: CrossOrderGateway {
    func charge(amount: Int) {}
    func settle() async {}
}

protocol CrossOrderAnalytics: Sendable {
    func track(event: String)
}

struct RealCrossOrderAnalytics: CrossOrderAnalytics {
    func track(event: String) {}
}

private final class OrderedVerificationGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var matcherEntered = false
    private var matcherReleased = false

    func matchAfterRelease(_ value: Int) -> Bool {
        condition.lock()
        matcherEntered = true
        condition.broadcast()
        while matcherReleased == false {
            condition.wait()
        }
        condition.unlock()
        return value == 42
    }

    func waitUntilMatcherEntered(within timeout: TimeInterval) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while matcherEntered == false {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    func releaseMatcher() {
        condition.lock()
        matcherReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

/// Shares the immutable runtime stub facade between the two verifier tasks.
/// Its recorder and fabricated storage provide their own synchronization.
private final class ConcurrentGatewayStub: @unchecked Sendable {
    let value: Stub<any CrossOrderGateway>

    init(_ value: Stub<any CrossOrderGateway>) {
        self.value = value
    }
}

@Suite struct CrossDoubleOrderTests {
    @Test func passesWhenInteractionsHappenedInTheVerifiedOrder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: any()) }.thenDoNothing()
        analytics.when { $0.track(event: any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: equal(42)) }
        order.verify(analytics) { $0.track(event: equal("purchase")) }
    }

    @Test func reportsWhenInteractionsHappenedInTheOppositeOrder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: any()) }.thenDoNothing()
        analytics.when { $0.track(event: any()) }.thenDoNothing()

        analytics().track(event: "purchase")
        gateway().charge(amount: 42)

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: any()) }
        expectReportsIssue {
            order.verify(analytics) { $0.track(event: any()) }
        } matching: {
            $0.description.contains("Ordered verification failed")
        }
    }

    @Test func unrelatedInterleavedCallsAreAllowed() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: any()) }.thenDoNothing()
        analytics.when { $0.track(event: any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "noise")
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: any()) }
        order.verify(analytics) { $0.track(event: equal("purchase")) }
    }

    @Test func cursorAdvancesWithinASingleDouble() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        gateway.when { $0.charge(amount: any()) }.thenDoNothing()

        gateway().charge(amount: 1)
        gateway().charge(amount: 2)

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: equal(2)) }
        expectReportsIssue {
            order.verify(gateway) { $0.charge(amount: equal(1)) }
        } matching: {
            $0.description.contains("Ordered verification failed")
        }
    }

    @Test func ordersAsyncAndSyncInteractionsAcrossDoubles() async throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        await gateway.when { await $0.settle() }.thenDoNothing()
        analytics.when { $0.track(event: any()) }.thenDoNothing()

        await gateway().settle()
        analytics().track(event: "settled")

        let order = InvocationOrder()
        await order.verify(gateway) { await $0.settle() }
        order.verify(analytics) { $0.track(event: equal("settled")) }
    }

    @Test(.timeLimit(.minutes(2)))
    func concurrentVerificationsCannotClaimTheSameInteraction() async throws {
        let gateway = ConcurrentGatewayStub(try Stub<any CrossOrderGateway>())
        gateway.value.when { $0.charge(amount: any()) }.thenDoNothing()
        gateway.value().charge(amount: 42)

        let order = InvocationOrder()
        let captor = ArgumentCaptor<Int>()
        let gate = OrderedVerificationGate()
        let blockedVerification = Task.detached(priority: Task.currentPriority) {
            expectReportsIssue {
                order.verify(gateway.value) {
                    $0.charge(
                        amount: allOf(
                            matching(description: "blocked", where: gate.matchAfterRelease),
                            captor.capture()
                        )
                    )
                }
            } matching: {
                $0.description.contains("Ordered verification failed")
            }
        }

        guard gate.waitUntilMatcherEntered(within: 60) else {
            gate.releaseMatcher()
            blockedVerification.cancel()
            await blockedVerification.value
            Issue.record("The blocking matcher did not start within 60 seconds.")
            return
        }

        order.verify(gateway.value) {
            $0.charge(amount: allOf(equal(42), captor.capture()))
        }
        gate.releaseMatcher()
        await blockedVerification.value

        #expect(captor.values == [42])
    }
}

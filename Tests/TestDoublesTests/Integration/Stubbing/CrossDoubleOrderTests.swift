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
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.equal(42)) }
        order.verify(analytics) { $0.track(event: Match.equal("purchase")) }
    }

    @Test func savedPatternsAndTerminalInteractionsComposeInOrder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        let charge = gateway.when {
            $0.charge(amount: Match.equal(42))
        }
        charge.thenDoNothing()
        let purchase = analytics.when {
            $0.track(event: Match.equal("purchase"))
        }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        InvocationOrder()
            .verify(charge)
            .verify(purchase)
            .verifyNoMoreInteractions()
    }

    @Test func savedPatternsReadAsAnOrderedBuilder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        let charge = gateway.when {
            $0.charge(amount: Match.equal(42))
        }
        charge.thenDoNothing()
        let purchase = analytics.when {
            $0.track(event: Match.equal("purchase"))
        }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        InvocationOrder(exhaustive: true) {
            charge
            purchase
        }
    }

    @Test func directInvocationsReadAsAnOrderedBuilder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()
        let gatewayValue: any CrossOrderGateway = gateway()
        let analyticsValue: any CrossOrderAnalytics = analytics()

        gatewayValue.charge(amount: 42)
        analyticsValue.track(event: "purchase")

        InvocationOrder(exhaustive: true) {
            gatewayValue.charge(amount: 42)
            analyticsValue.track(event: Match.equal("purchase"))
        }

        #expect(gateway.history.callCount == 1)
        #expect(analytics.history.callCount == 1)
    }

    @Test func directAsyncInvocationsReadAsAnOrderedBuilder() async throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        await gateway.when { await $0.settle() }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()
        let gatewayValue: any CrossOrderGateway = gateway()
        let analyticsValue: any CrossOrderAnalytics = analytics()

        await gatewayValue.settle()
        analyticsValue.track(event: "settled")

        await InvocationOrder(exhaustive: true) {
            await gatewayValue.settle()
            analyticsValue.track(event: "settled")
        }

        #expect(gateway.history.callCount == 1)
        #expect(analytics.history.callCount == 1)
    }

    @Test func nonexhaustiveBuilderAcceptsAnOrderedSubsequence() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        let charge = gateway.when {
            $0.charge(amount: Match.equal(42))
        }
        charge.thenDoNothing()
        let purchase = analytics.when {
            $0.track(event: Match.equal("purchase"))
        }
        purchase.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "noise")
        analytics().track(event: "purchase")
        analytics().track(event: "after")

        InvocationOrder {
            charge
            purchase
        }
    }

    @Test func exhaustiveBuilderReportsInteractionsOutsideTheSequence() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        let charge = gateway.when {
            $0.charge(amount: Match.equal(42))
        }
        charge.thenDoNothing()
        let purchase = analytics.when {
            $0.track(event: Match.equal("purchase"))
        }
        purchase.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "noise")
        analytics().track(event: "purchase")

        expectReportsIssue {
            InvocationOrder(exhaustive: true) {
                charge
                purchase
            }
        } matching: {
            $0.description.contains("noise")
        }
    }

    @Test func builderSupportsConditionalsAndLoops() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let first = gateway.when {
            $0.charge(amount: Match.equal(1))
        }
        first.thenDoNothing()
        let second = gateway.when {
            $0.charge(amount: Match.equal(2))
        }
        second.thenDoNothing()
        let patterns = [first, second]
        let includeSettledState = false

        gateway().charge(amount: 1)
        gateway().charge(amount: 2)

        InvocationOrder(exhaustive: true) {
            for pattern in patterns {
                pattern
            }
            if includeSettledState {
                first
            }
        }
    }

    @Test func scopedContextClosesDirectExpectationsExhaustively() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        InvocationOrder(exhaustive: true) { order in
            order.verify(gateway) { $0.charge(amount: Match.equal(42)) }
            order.verify(analytics) {
                $0.track(event: Match.equal("purchase"))
            }
        }
    }

    @Test func asyncScopedContextClosesDirectExpectationsExhaustively() async throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        await gateway.when { await $0.settle() }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        await gateway().settle()
        analytics().track(event: "settled")

        await InvocationOrder(exhaustive: true) { order in
            await order.verify(gateway) { await $0.settle() }
            order.verify(analytics) {
                $0.track(event: Match.equal("settled"))
            }
        }
    }

    @Test func reportsWhenInteractionsHappenedInTheOppositeOrder() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        analytics().track(event: "purchase")
        gateway().charge(amount: 42)

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.any()) }
        expectReportsIssue {
            order.verify(analytics) { $0.track(event: Match.any()) }
        } matching: {
            $0.description.contains("Ordered verification failed")
        }
    }

    @Test func unrelatedInterleavedCallsAreAllowed() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "noise")
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.any()) }
        order.verify(analytics) { $0.track(event: Match.equal("purchase")) }
    }

    @Test func cursorAdvancesWithinASingleDouble() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 1)
        gateway().charge(amount: 2)

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.equal(2)) }
        expectReportsIssue {
            order.verify(gateway) { $0.charge(amount: Match.equal(1)) }
        } matching: {
            $0.description.contains("Ordered verification failed")
        }
    }

    @Test func ordersAsyncAndSyncInteractionsAcrossDoubles() async throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        await gateway.when { await $0.settle() }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        await gateway().settle()
        analytics().track(event: "settled")

        let order = InvocationOrder()
        await order.verify(gateway) { await $0.settle() }
        order.verify(analytics) { $0.track(event: Match.equal("settled")) }
    }

    @Test(.timeLimit(.minutes(2)))
    func concurrentVerificationsCannotClaimTheSameInteraction() async throws {
        let gateway = ConcurrentGatewayStub(try Stub<any CrossOrderGateway>())
        gateway.value.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        gateway.value().charge(amount: 42)

        let order = InvocationOrder()
        let captor = Match.Capture<Int>()
        let gate = OrderedVerificationGate()
        let blockedVerification = Task {
            expectReportsIssue {
                order.verify(gateway.value) {
                    $0.charge(
                        amount: Match.allOf(
                            Match.matching(description: "blocked", where: gate.matchAfterRelease),
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
            $0.charge(amount: Match.allOf(Match.equal(42), captor.capture()))
        }
        gate.releaseMatcher()
        await blockedVerification.value

        #expect(captor.values == [42])
    }

    @Test func verifyNoMoreInteractionsPassesWhenEveryTouchedDoublesCallsAreVerified() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.equal(42)) }
        order.verify(analytics) { $0.track(event: Match.equal("purchase")) }
        order.verifyNoMoreInteractions()
    }

    @Test func verifyNoMoreInteractionsReportsAnUnverifiedCallOnATouchedDouble() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")
        analytics().track(event: "extra")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.equal(42)) }
        order.verify(analytics) { $0.track(event: Match.equal("purchase")) }

        expectReportsIssue {
            order.verifyNoMoreInteractions()
        } matching: {
            $0.description.contains("extra")
        }
    }

    @Test func verifyNoMoreInteractionsIgnoresDoublesNeverVerifiedThroughThisSession() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        let analytics = try Stub<any CrossOrderAnalytics>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()
        analytics.when { $0.track(event: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)
        analytics().track(event: "purchase")

        let order = InvocationOrder()
        order.verify(gateway) { $0.charge(amount: Match.equal(42)) }

        // `analytics` recorded a call but was never touched through `order`,
        // so it is out of scope for this session's verifyNoMoreInteractions().
        order.verifyNoMoreInteractions()
    }

    @Test func verifyNoMoreInteractionsIgnoresDoublesWhoseOrderVerificationFailed() throws {
        let gateway = try Stub<any CrossOrderGateway>()
        gateway.when { $0.charge(amount: Match.any()) }.thenDoNothing()

        gateway().charge(amount: 42)

        let order = InvocationOrder()
        expectReportsIssue {
            order.verify(gateway) { $0.charge(amount: Match.equal(7)) }
        } matching: {
            $0.description.contains("Ordered verification failed")
        }

        // A failed step must not bring this otherwise unverified double into
        // the session-wide verification scope.
        order.verifyNoMoreInteractions()
    }
}

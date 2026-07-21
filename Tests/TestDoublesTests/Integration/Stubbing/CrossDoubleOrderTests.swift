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
}

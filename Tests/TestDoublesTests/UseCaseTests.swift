import Testing
@testable import TestDoubles
import TestDoublesFixtures

@Suite struct RepositoryUseCaseTests {
    @Test func configuresSpecificAndFallbackResults() throws {
        let repository = try Stub<any UserRepository>()
        repository.when { $0.find(id: equal(1)) }.returns("Alice")
        repository.when { $0.find(id: any()) }.returns("Unknown")
        repository.when { $0.count }.returns(1)

        let users: any UserRepository = repository()
        #expect(users.find(id: 1) == "Alice")
        #expect(users.find(id: 999) == "Unknown")
        #expect(users.count == 1)
    }

    @Test func computesResponsesFromArguments() throws {
        let repository = try Stub<any UserRepository>()
        repository.when { $0.find(id: any()) }.then { (id: Int) in
            id < 100 ? "User_\(id)" : "VIP_\(id)"
        }

        #expect(repository().find(id: 42) == "User_42")
        #expect(repository().find(id: 150) == "VIP_150")
    }

    @Test func verifiesAndCapturesSearches() throws {
        let repository = try Stub<any UserRepository>()
        repository.when { $0.search(query: any()) }.returns(["result"])
        let users: any UserRepository = repository()
        _ = users.search(query: "alice")
        _ = users.search(query: "bob")

        let queries = ArgumentCaptor<String>()
        repository.verify(.exactly(2)) { $0.search(query: queries.capture()) }
        repository.verify(.never) { $0.find(id: any()) }
        #expect(queries.values == ["alice", "bob"])
    }
}

@Suite struct ServiceLayerUseCaseTests {
    @Test func coordinatesMultipleDependencies() throws {
        let repository = try Stub<any UserRepository>()
        let notifications = try Stub<any NotificationService>()
        repository.when { $0.find(id: 1) }.returns("Alice")
        notifications.when { try $0.send(to: any(), message: any()) }

        let users: any UserRepository = repository()
        let notifier: any NotificationService = notifications()
        let name = users.find(id: 1)
        try notifier.send(to: 1, message: "Welcome, \(name)!")

        repository.verify(.exactly(1)) { $0.find(id: 1) }
        notifications.verify(.exactly(1)) {
            try $0.send(to: 1, message: "Welcome, Alice!")
        }
    }

    @Test func modelsPaymentResults() throws {
        let gateway = try Stub<any PaymentGateway>()
        let charged = PaymentResult(transactionId: "tx-001", amount: 99.99, success: true)
        gateway.when { try $0.charge(amount: any(), currency: equal("USD")) }.returns(charged)
        gateway.when { $0.supportedCurrencies }.returns(["USD", "EUR"])
        gateway.when { $0.isAvailable }.returns(true)

        let payments: any PaymentGateway = gateway()
        #expect(payments.isAvailable)
        #expect(payments.supportedCurrencies.contains("EUR"))
        #expect(try payments.charge(amount: 99.99, currency: "USD") == charged)
    }

    @Test func handlesThrowingVoidAndCollectionRequirements() throws {
        let notifications = try Stub<any NotificationService>()
        notifications.when { try $0.send(to: any(), message: any()) }
        notifications.when { try $0.sendBulk(to: any(), message: any()) }.returns(3)
        notifications.when { $0.pending(for: any()) }.then { (id: Int) in
            id == 1 ? ["Alert", "Reminder"] : []
        }
        notifications.when { $0.markRead(notificationId: any()) }
        notifications.when { $0.unreadCount }.returns(2)

        let service: any NotificationService = notifications()
        try service.send(to: 1, message: "Hello")
        #expect(try service.sendBulk(to: [1, 2, 3], message: "Update") == 3)
        #expect(service.pending(for: 1) == ["Alert", "Reminder"])
        service.markRead(notificationId: "n-1")

        notifications.verify { try $0.send(to: 1, message: "Hello") }
        notifications.verify { $0.markRead(notificationId: "n-1") }
    }
}

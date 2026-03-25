import Testing
@testable import TestDoubles

// MARK: - Realistic service layer testing

/// Simulates testing a service that depends on a repository.
@Suite struct RepositoryTests {

    @Test func findUserById() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: 1) }.returns("Alice")
        repo.when { $0.find(id: 2) }.returns("Bob")
        repo.when { $0.find(id: any()) }.returns("Unknown")
        repo.when { $0.count }.returns(2)

        let sut: any UserRepository = repo()

        #expect(sut.find(id: 1) == "Alice")
        #expect(sut.find(id: 2) == "Bob")
        #expect(sut.find(id: 999) == "Unknown")
    }

    @Test func searchReturnsFilteredResults() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.search(query: equal("al")) }.returns(["Alice"])
        repo.when { $0.search(query: any()) }.returns([])
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()

        #expect(sut.search(query: "al") == ["Alice"])
        #expect(sut.search(query: "zzz") == [])
    }

    @Test func dynamicResponseBasedOnInput() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: any()) }.then { args in
            let id = args[0] as! Int
            return id < 100 ? "User_\(id)" : "VIP_\(id)"
        }
        repo.when { $0.count }.returns(200)

        let sut: any UserRepository = repo()

        #expect(sut.find(id: 42) == "User_42")
        #expect(sut.find(id: 150) == "VIP_150")
    }

    @Test func verifyMethodWasCalledWithCorrectArgs() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: any()) }.returns("X")
        repo.when { $0.search(query: any()) }.returns([])
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()
        _ = sut.find(id: 42)
        _ = sut.search(query: "test")
        _ = sut.search(query: "other")

        repo.verify(called: 1) { $0.find(id: any()) }
        repo.verify(called: 2) { $0.search(query: any()) }
        repo.verify(never: { $0.find(id: 999) })
    }

    @Test func captureAndInspectArguments() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.search(query: any()) }.returns(["result"])
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()
        _ = sut.search(query: "alice")
        _ = sut.search(query: "bob")
        _ = sut.search(query: "charlie")

        let captor = ArgumentCaptor<String>()
        repo.verify { $0.search(query: captor.capture()) }.wasCalled(times: 3)
        #expect(captor.values == ["alice", "bob", "charlie"])
        #expect(captor.last == "charlie")
    }

    @Test func orderedVerification() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: any()) }.returns("X")
        repo.when { $0.search(query: any()) }.returns([])
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()
        _ = sut.find(id: 1)
        _ = sut.search(query: "test")

        repo.verifyOrder {
            $0.find(id: any())
            $0.search(query: any())
        }
    }
}

// MARK: - File service (throwing methods)

@Suite struct FileServiceTests {

    @Test func readAndWriteHappyPath() throws {
        let fs = RuntimeStub<any ThrowingFileService>()
        fs.when { try $0.read(path: equal("/config.json")) }.returns("{}")
        fs.when { try $0.read(path: any()) }.returns("")
        fs.when { try $0.write(path: any(), content: any()) }
        fs.when { $0.exists(at: any()) }.returns(true)
        fs.when { $0.basePath }.returns("/app")

        let sut: any ThrowingFileService = fs()

        #expect(try sut.read(path: "/config.json") == "{}")
        #expect(try sut.read(path: "/other.txt") == "")
        #expect(throws: Never.self) { try sut.write(path: "/out.txt", content: "data") }
        #expect(sut.basePath == "/app")
    }

    @Test func verifyWriteWasCalled() throws {
        let fs = RuntimeStub<any ThrowingFileService>()
        fs.when { try $0.read(path: any()) }.returns("")
        fs.when { try $0.write(path: any(), content: any()) }
        fs.when { $0.exists(at: any()) }.returns(true)
        fs.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = fs()
        try sut.write(path: "/log.txt", content: "entry")

        fs.verify(called: 1) { try $0.write(path: any(), content: any()) }
        fs.verify(never: { try $0.read(path: any()) })
    }

    @Test func conditionalExistence() {
        let fs = RuntimeStub<any ThrowingFileService>()
        fs.when { $0.exists(at: equal("/real.txt")) }.returns(true)
        fs.when { $0.exists(at: any()) }.returns(false)
        fs.when { try $0.read(path: any()) }.returns("")
        fs.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = fs()

        #expect(sut.exists(at: "/real.txt") == true)
        #expect(sut.exists(at: "/missing.txt") == false)
    }
}

// MARK: - Notification service (void + collection + throwing)

@Suite struct NotificationServiceTests {

    @Test func sendAndVerify() throws {
        let svc = RuntimeStub<any NotificationService>()
        svc.when { try $0.send(to: any(), message: any()) }
        svc.when { try $0.sendBulk(to: any(), message: any()) }.returns(3)
        svc.when { $0.pending(for: any()) }.returns(["Welcome!"])
        svc.when { $0.markRead(notificationId: any()) }
        svc.when { $0.unreadCount }.returns(5)

        let sut: any NotificationService = svc()

        try sut.send(to: 42, message: "Hello")
        let sent = try sut.sendBulk(to: [1, 2, 3], message: "Update")
        #expect(sent == 3)
        #expect(sut.pending(for: 42) == ["Welcome!"])
        #expect(sut.unreadCount == 5)

        sut.markRead(notificationId: "n-1")

        svc.verify(called: 1) { try $0.send(to: any(), message: any()) }
        svc.verify(called: 1) { $0.markRead(notificationId: any()) }
    }

    @Test func dynamicPendingNotifications() {
        let svc = RuntimeStub<any NotificationService>()
        svc.when { $0.pending(for: any()) }.then { args in
            let userId = args[0] as! Int
            return userId == 1 ? ["Alert", "Reminder"] : []
        }
        svc.when { $0.unreadCount }.returns(0)

        let sut: any NotificationService = svc()

        #expect(sut.pending(for: 1) == ["Alert", "Reminder"])
        #expect(sut.pending(for: 99) == [])
    }
}

// MARK: - Multiple stubs in one test (integration-style)

@Suite struct IntegrationStyleTests {

    @Test func serviceLayerWithMultipleDependencies() throws {
        let repo = RuntimeStub<any UserRepository>()
        let notifier = RuntimeStub<any NotificationService>()

        repo.when { $0.find(id: 1) }.returns("Alice")
        repo.when { $0.count }.returns(1)

        notifier.when { try $0.send(to: any(), message: any()) }
        notifier.when { $0.unreadCount }.returns(0)

        let user: any UserRepository = repo()
        let notify: any NotificationService = notifier()

        // Simulate: find user, then send notification
        let name = user.find(id: 1)
        try notify.send(to: 1, message: "Welcome, \(name)!")

        repo.verify(called: 1) { $0.find(id: 1) }
        notifier.verify(called: 1) { try $0.send(to: any(), message: any()) }
    }

    @Test func paymentGatewayChargeAndRefund() throws {
        let gateway = RuntimeStub<any PaymentGateway>()
        let chargeResult = PaymentResult(transactionId: "tx-001", amount: 99.99, success: true)
        let refundResult = PaymentResult(transactionId: "tx-001", amount: 99.99, success: true)

        gateway.when { try $0.charge(amount: any(), currency: any()) }.returns(chargeResult)
        gateway.when { try $0.refund(transactionId: any()) }.returns(refundResult)
        gateway.when { $0.supportedCurrencies }.returns(["USD", "EUR", "GBP"])
        gateway.when { $0.isAvailable }.returns(true)

        let sut: any PaymentGateway = gateway()

        #expect(sut.isAvailable)
        #expect(sut.supportedCurrencies.contains("EUR"))

        let charge = try sut.charge(amount: 99.99, currency: "USD")
        #expect(charge.success)
        #expect(charge.transactionId == "tx-001")

        let refund = try sut.refund(transactionId: "tx-001")
        #expect(refund.success)
    }
}

// MARK: - Matcher showcase

@Suite struct MatcherShowcaseTests {

    @Test func predicateMatching() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
        repo.when { $0.find(id: any(where: { $0 > 0 })) }.returns("Regular")
        repo.when { $0.find(id: any()) }.returns("Guest")
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()

        // Specificity: equal > predicate > any
        #expect(sut.find(id: 200) == "VIP")
        #expect(sut.find(id: 50) == "Regular")
        #expect(sut.find(id: -1) == "Guest")
    }

    @Test func equalMatcher() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: equal(42)) }.returns("The Answer")
        repo.when { $0.find(id: any()) }.returns("default")
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()

        #expect(sut.find(id: 42) == "The Answer")
        #expect(sut.find(id: 43) == "default")
    }

    @Test func callLogInspection() {
        let repo = RuntimeStub<any UserRepository>()
        repo.when { $0.find(id: any()) }.returns("X")
        repo.when { $0.count }.returns(0)

        let sut: any UserRepository = repo()
        _ = sut.find(id: 1)
        _ = sut.find(id: 2)
        _ = sut.count

        #expect(repo.calls.count == 3)
    }
}

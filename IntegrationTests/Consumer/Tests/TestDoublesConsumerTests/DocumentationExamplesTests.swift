import Testing
import TestDoubles

protocol UserRepository {
    func find(id: Int) -> String
}

struct LiveUserRepository: UserRepository {
    func find(id: Int) -> String { "" }
}

protocol NotificationService {
    func send(to userID: Int, message: String) throws
}

struct LiveNotificationService: NotificationService {
    func send(to userID: Int, message: String) throws {}
}

protocol AsyncDataLoader {
    func load(url: String) async throws -> String
    func prefetch(urls: [String]) async
    var cacheSize: Int { get }
}

struct LiveDataLoader: AsyncDataLoader {
    func load(url: String) async throws -> String { "" }
    func prefetch(urls: [String]) async {}
    var cacheSize: Int { 0 }
}

protocol PrototypeCalculator {
    func add(_ lhs: Int, _ rhs: Int) -> Int
    func describe(_ value: Int) -> String
    var precision: Int { get }
}

private struct LoadError: Error, Equatable {
    let url: String
}

@Suite("Documentation examples")
struct DocumentationExamplesTests {
    @Test("Matcher specificity selects repository responses")
    func repositoryMatching() throws {
        let stub = try Stub<any UserRepository>()
        stub.when { $0.find(id: any()) }.returns("guest")
        stub.when {
            $0.find(id: matching(description: "positive", where: { $0 > 0 }))
        }.then { (id: Int) in
            "member-\(id)"
        }
        stub.when { $0.find(id: equal(42)) }.returns("Alice")

        let repository: any UserRepository = stub()
        #expect(repository.find(id: -1) == "guest")
        #expect(repository.find(id: 7) == "member-7")
        #expect(repository.find(id: 42) == "Alice")

        stub.verify { $0.find(id: equal(42)) }
        stub.verify(.exactly(3)) { $0.find(id: any()) }
        stub.verify(.never) { $0.find(id: equal(999)) }
    }

    @Test("Capture arguments sent to a side-effect dependency")
    func capturesSideEffects() throws {
        let stub = try Stub<any NotificationService>()
        stub.when { try $0.send(to: any(), message: any()) }

        let notifications: any NotificationService = stub()
        try notifications.send(to: 1, message: "Welcome")
        try notifications.send(to: 2, message: "Try again")

        let recipients = ArgumentCaptor<Int>()
        let messages = ArgumentCaptor<String>()
        stub.verify(.exactly(2)) {
            try $0.send(to: recipients.capture(), message: messages.capture())
        }
        #expect(recipients.values == [1, 2])
        #expect(messages.values == ["Welcome", "Try again"])
    }

    @Test("Async handlers suspend, return values, and throw errors")
    func handlesAsyncSuccessAndFailure() async throws {
        let stub = try Stub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: equal("/users/42")) }.then {
            (url: String) async throws -> String in
            await Task.yield()
            return "profile:\(url)"
        }
        await stub.when { try await $0.load(url: any()) }.then {
            (url: String) async throws -> String in
            await Task.yield()
            throw LoadError(url: url)
        }

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "/users/42") == "profile:/users/42")
        let error = await #expect(throws: LoadError.self) {
            try await loader.load(url: "/missing")
        }
        #expect(error?.url == "/missing")

        await stub.verify(.exactly(2)) { try await $0.load(url: any()) }
    }

    @Test("A handler can return a stateful response sequence")
    func returnsStatefulSequence() throws {
        let stub = try Stub<any UserRepository>()
        var responses = ["syncing", "ready"]
        stub.when { $0.find(id: equal(42)) }.then { (_: Int) in
            responses.removeFirst()
        }

        let repository: any UserRepository = stub()
        #expect(repository.find(id: 42) == "syncing")
        #expect(repository.find(id: 42) == "ready")
        stub.verify(.exactly(2)) { $0.find(id: equal(42)) }
    }

    @Test("Explicit requirements work without a linked conformer")
    func constructsFromExplicitRequirements() throws {
        let stub = try Stub<any PrototypeCalculator>(
            .method(Int.self, Int.self, returning: Int.self),
            .method(Int.self, returning: String.self),
            .getter(Int.self)
        )
        stub.when { $0.add(any(), any()) }.then { (lhs: Int, rhs: Int) in
            lhs + rhs
        }
        stub.when { $0.describe(any()) }.then { (value: Int) in
            "value=\(value)"
        }
        stub.when { $0.precision }.returns(2)

        let calculator: any PrototypeCalculator = stub()
        #expect(calculator.add(20, 22) == 42)
        #expect(calculator.describe(42) == "value=42")
        #expect(calculator.precision == 2)
    }
}

import Testing
@testable import TestDoubles
import TestDoublesFixtures

protocol MatcherService {
    func find(id: Int) -> String
    func search(query: String, limit: Int) -> [String]
}

struct RealMatcherService: MatcherService {
    func find(id: Int) -> String { "" }
    func search(query: String, limit: Int) -> [String] { [] }
}

@Suite struct MatcherTests {
    @Test func matchingSupportsDefaultAndNamedDescriptions() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: matching(where: { $0.hasPrefix("test") }), limit: any()) }
            .returns(["test"])
        stub.when {
            $0.search(
                query: matching(description: "admin", where: { $0.hasPrefix("admin") }),
                limit: any()
            )
        }
            .returns(["admin"])
        stub.when { $0.search(query: any(), limit: any()) }.returns([])

        #expect(stub().search(query: "test.users", limit: 10) == ["test"])
        #expect(stub().search(query: "admin.users", limit: 10) == ["admin"])
        #expect(stub().search(query: "public.users", limit: 10).isEmpty)
    }

    @Test func captorCollectsValuesDuringVerification() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.returns("X")
        let service: any MatcherService = stub()
        _ = service.find(id: 7)
        _ = service.find(id: 13)

        let ids = ArgumentCaptor<Int>()
        stub.verify(.exactly(2)) { $0.find(id: ids.capture()) }

        #expect(ids.values == [7, 13])
        #expect(ids.first == 7)
        #expect(ids.last == 13)
        ids.reset()
        #expect(ids.values.isEmpty)
    }

    @Test func captorCommitsOnlyAfterEveryArgumentMatches() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        let service: any MatcherService = stub()
        _ = service.search(query: "rejected", limit: 1)
        _ = service.search(query: "accepted", limit: 2)

        let queries = ArgumentCaptor<String>()
        stub.verify(.exactly(1)) {
            $0.search(query: queries.capture(), limit: equal(2))
        }

        #expect(queries.values == ["accepted"])
    }
}

@Suite struct TypedThenTests {
    @Test func zeroOneAndTwoArgumentHandlers() throws {
        let stub = try Stub<any MatcherService>()
        stub.when { $0.find(id: any()) }.then { (id: Int) in "user_\(id)" }
        stub.when { $0.search(query: any(), limit: any()) }.then {
            (query: String, limit: Int) in
            Array(repeating: query, count: limit)
        }

        #expect(stub().find(id: 42) == "user_42")
        #expect(stub().search(query: "x", limit: 3) == ["x", "x", "x"])
    }

    @Test func typedThrowingHandlerPropagates() throws {
        struct ReadError: Error, Equatable { let path: String }
        let stub = try Stub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { (path: String) throws in
            if path == "/missing" { throw ReadError(path: path) }
            return "content:\(path)"
        }

        #expect(try stub().read(path: "/ok") == "content:/ok")
        let error = #expect(throws: ReadError.self) {
            try stub().read(path: "/missing")
        }
        #expect(error?.path == "/missing")
    }
}

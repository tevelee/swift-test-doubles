import Testing
@testable import TestDoubles

protocol MatcherTestService {
    func find(id: Int) -> String
    func search(query: String, limit: Int) -> [String]
    var count: Int { get }
}
struct RealMatcherTestService: MatcherTestService {
    func find(id: Int) -> String { "" }
    func search(query: String, limit: Int) -> [String] { [] }
    var count: Int { 0 }
}

@Suite struct PredicateMatcherTests {
    @Test func filterByPredicate() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
        stub.when { $0.find(id: any(where: { $0 <= 100 })) }.returns("Regular")
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        #expect(sut.find(id: 101) == "VIP")
        #expect(sut.find(id: 50) == "Regular")
    }

    @Test func evenOdd() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any(where: { $0 % 2 == 0 })) }.returns("Even")
        stub.when { $0.find(id: any()) }.returns("Odd")
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        #expect(sut.find(id: 2) == "Even")
        #expect(sut.find(id: 3) == "Odd")
    }

    @Test func stringPredicate() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.search(query: any(where: { $0.hasPrefix("test") }), limit: any()) }.returns(["result"])
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        #expect(sut.search(query: "test_query", limit: 10) == ["result"])
        #expect(sut.search(query: "other", limit: 10) == [])
    }
}

@Suite struct SpecificityTests {
    @Test func equalBeatsPredicate() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("catch-all")
        stub.when { $0.find(id: any(where: { $0 > 0 })) }.returns("positive")
        stub.when { $0.find(id: equal(42)) }.returns("the answer")
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        #expect(sut.find(id: 42) == "the answer")
        #expect(sut.find(id: 10) == "positive")
        #expect(sut.find(id: -5) == "catch-all")
    }

    @Test func exactValueBeatsAny() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("default")
        stub.when { $0.find(id: 42) }.returns("exact")
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        #expect(sut.find(id: 42) == "exact")
        #expect(sut.find(id: 99) == "default")
    }
}

@Suite struct ArgumentCaptorTests {
    @Test func singleValue() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)
        _ = stub().find(id: 42)
        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.find(id: captor.capture()) }.wasCalled()
        #expect(captor.values == [42])
    }

    @Test func multipleValues() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        _ = sut.find(id: 1); _ = sut.find(id: 2); _ = sut.find(id: 3)
        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.find(id: captor.capture()) }.wasCalled(times: 3)
        #expect(captor.values == [1, 2, 3])
    }

    @Test func twoArguments() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        stub.when { $0.count }.returns(0)
        let sut: any MatcherTestService = stub()
        _ = sut.search(query: "alice", limit: 10)
        _ = sut.search(query: "bob", limit: 20)
        let q = ArgumentCaptor<String>(), l = ArgumentCaptor<Int>()
        stub.verify { $0.search(query: q.capture(), limit: l.capture()) }.wasCalled(times: 2)
        #expect(q.values == ["alice", "bob"])
        #expect(l.values == [10, 20])
    }
}

@Suite struct ThenTests {
    @Test func returnValue() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.then { return "hello" }
        stub.when { $0.count }.returns(0)
        #expect(stub().find(id: 1) == "hello")
    }

    @Test func withArguments() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.then { args in return "user_\(args[0])" }
        stub.when { $0.count }.returns(0)
        #expect(stub().find(id: 42) == "user_42")
    }

    @Test func multipleArgs() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.search(query: any(), limit: any()) }.then { args in
            let q = args[0] as! String, n = args[1] as! Int
            return Array(repeating: q, count: n)
        }
        stub.when { $0.count }.returns(0)
        #expect(stub().search(query: "x", limit: 3) == ["x", "x", "x"])
    }

    @Test func throwingHappyPath() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { return "content" }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")
        #expect(try stub().read(path: "/test") == "content")
    }

    @Test func throwRegistersStub() {
        struct E: Error {}
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { throw E() }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")
        #expect(stub.recorder.throwingStubs[0] != nil)
    }

    @Test func conditionalThrowHandler() throws {
        struct ReadError: Error, Equatable { let path: String }
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { args in
            let path = args[0] as! String
            if path.hasPrefix("/private") { throw ReadError(path: path) }
            return "contents of \(path)"
        }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        #expect(try stub().read(path: "/public/file") == "contents of /public/file")
        let handler = stub.recorder.throwingStubs[0]![0].handler
        #expect(throws: ReadError.self) { try handler(["/private/secret"]) }
    }
}

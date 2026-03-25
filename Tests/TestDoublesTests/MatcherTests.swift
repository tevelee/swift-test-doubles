import XCTest
import TestDoubles

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

final class MatcherTests: XCTestCase {

    // MARK: - any(where:) predicate matcher

    func testAnyWhere_FiltersByPredicate() {
        let stub = RuntimeStub<any MatcherTestService>()

        stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
        stub.when { $0.find(id: any(where: { $0 <= 100 })) }.returns("Regular")
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()

        XCTAssertEqual(sut.find(id: 101), "VIP")
        XCTAssertEqual(sut.find(id: 200), "VIP")
        XCTAssertEqual(sut.find(id: 50), "Regular")
        XCTAssertEqual(sut.find(id: 1), "Regular")
    }

    func testAnyWhere_EvenOdd() {
        let stub = RuntimeStub<any MatcherTestService>()

        stub.when { $0.find(id: any(where: { $0 % 2 == 0 })) }.returns("Even")
        stub.when { $0.find(id: any()) }.returns("Odd")
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()

        XCTAssertEqual(sut.find(id: 2), "Even")
        XCTAssertEqual(sut.find(id: 4), "Even")
        XCTAssertEqual(sut.find(id: 3), "Odd")
        XCTAssertEqual(sut.find(id: 7), "Odd")
    }

    func testAnyWhere_StringPredicate() {
        let stub = RuntimeStub<any MatcherTestService>()

        stub.when { $0.search(query: any(where: { $0.hasPrefix("test") }), limit: any()) }
            .returns(["result"])
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()

        XCTAssertEqual(sut.search(query: "test_query", limit: 10), ["result"])
        XCTAssertEqual(sut.search(query: "other", limit: 10), [])
    }

    // MARK: - Specificity ordering

    func testSpecificity_EqualBeatsPredicateBeatsAny() {
        let stub = RuntimeStub<any MatcherTestService>()

        // Register in any order — specificity determines which wins
        stub.when { $0.find(id: any()) }.returns("catch-all")                        // specificity 0
        stub.when { $0.find(id: any(where: { $0 > 0 })) }.returns("positive")       // specificity 1
        stub.when { $0.find(id: equal(42)) }.returns("the answer")                   // specificity 3
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()

        XCTAssertEqual(sut.find(id: 42), "the answer")   // equal wins (3)
        XCTAssertEqual(sut.find(id: 10), "positive")     // predicate wins (1)
        XCTAssertEqual(sut.find(id: -5), "catch-all")    // only any matches (0)
    }

    func testSpecificity_ExactValueBeatsAny() {
        let stub = RuntimeStub<any MatcherTestService>()

        stub.when { $0.find(id: any()) }.returns("default")
        stub.when { $0.find(id: 42) }.returns("exact")  // raw value → DescriptionMatcher (2)
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()

        XCTAssertEqual(sut.find(id: 42), "exact")
        XCTAssertEqual(sut.find(id: 99), "default")
    }

    // MARK: - ArgumentCaptor

    func testArgumentCaptor_CapturesSingleValue() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        _ = sut.find(id: 42)

        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.find(id: captor.capture()) }.wasCalled()
        XCTAssertEqual(captor.values, [42])
        XCTAssertEqual(captor.last, 42)
    }

    func testArgumentCaptor_CapturesMultipleValues() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        _ = sut.find(id: 1)
        _ = sut.find(id: 2)
        _ = sut.find(id: 3)

        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.find(id: captor.capture()) }.wasCalled(times: 3)
        XCTAssertEqual(captor.values, [1, 2, 3])
        XCTAssertEqual(captor.first, 1)
        XCTAssertEqual(captor.last, 3)
    }

    func testArgumentCaptor_CapturesStringArgs() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        _ = sut.search(query: "alice", limit: 10)
        _ = sut.search(query: "bob", limit: 20)

        let queryCaptor = ArgumentCaptor<String>()
        let limitCaptor = ArgumentCaptor<Int>()
        stub.verify { $0.search(query: queryCaptor.capture(), limit: limitCaptor.capture()) }
            .wasCalled(times: 2)

        XCTAssertEqual(queryCaptor.values, ["alice", "bob"])
        XCTAssertEqual(limitCaptor.values, [10, 20])
    }

    // MARK: - Unified .then API

    func testThen_ReturnValue() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.then { return "hello" }
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        XCTAssertEqual(sut.find(id: 1), "hello")
    }

    func testThen_WithArguments() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.then { args in return "user_\(args[0])" }
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        XCTAssertEqual(sut.find(id: 42), "user_42")
        XCTAssertEqual(sut.find(id: 7), "user_7")
    }

    func testThen_MultipleArgs() {
        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.search(query: any(), limit: any()) }.then { args in
            let q = args[0] as! String
            let limit = args[1] as! Int
            return Array(repeating: q, count: limit)
        }
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        XCTAssertEqual(sut.search(query: "x", limit: 3), ["x", "x", "x"])
    }

    func testThen_ThrowingHappyPath() {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { "content" }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()
        XCTAssertEqual(try sut.read(path: "/test"), "content")
    }

    func testThen_DynamicWithArgs() {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.then { args in
            "contents of \(args[0])"
        }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()
        XCTAssertEqual(try sut.read(path: "/readme"), "contents of /readme")
        XCTAssertEqual(try sut.read(path: "/config"), "contents of /config")
    }

    func testArgumentCaptor_Reset() {
        let captor = ArgumentCaptor<Int>()

        let stub = RuntimeStub<any MatcherTestService>()
        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.count }.returns(0)

        let sut: any MatcherTestService = stub()
        _ = sut.find(id: 1)

        stub.verify { $0.find(id: captor.capture()) }.wasCalled()
        XCTAssertEqual(captor.values, [1])

        captor.reset()
        XCTAssertTrue(captor.values.isEmpty)
    }
}

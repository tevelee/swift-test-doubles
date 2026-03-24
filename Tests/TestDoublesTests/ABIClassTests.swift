import XCTest
import TestDoubles

// Protocol with collection return types (Array, Set, Dictionary)
// These are NOT in the per-type thunk catalog — they use ABI-class fallback.
protocol CollectionService {
    func fetchItems(query: String) -> [Int]
    func allTags() -> [String]
    var count: Int { get }
}

struct RealCollectionService: CollectionService {
    func fetchItems(query: String) -> [Int] { [] }
    func allTags() -> [String] { [] }
    var count: Int { 0 }
}

// Protocol mixing known types (Int, String) with collection returns
protocol MixedReturnService {
    func name() -> String
    func items() -> [String]
    var total: Int { get }
}

struct RealMixedReturnService: MixedReturnService {
    func name() -> String { "" }
    func items() -> [String] { [] }
    var total: Int { 0 }
}

final class ABIClassTests: XCTestCase {

    func testCollectionReturnTypes() {
        let stub = RuntimeStub<any CollectionService>()

        stub.when { $0.fetchItems(query: "test") }.returns([10, 20, 30])
        stub.when { $0.allTags() }.returns(["swift", "echo"])
        stub.when { $0.count }.returns(99)

        let sut: any CollectionService = stub()

        XCTAssertEqual(sut.fetchItems(query: "test"), [10, 20, 30])
        XCTAssertEqual(sut.allTags(), ["swift", "echo"])
        XCTAssertEqual(sut.count, 99)
    }

    func testMixedKnownAndCollectionReturns() {
        let stub = RuntimeStub<any MixedReturnService>()

        stub.when { $0.name() }.returns("MockName")
        stub.when { $0.items() }.returns(["a", "b", "c"])
        stub.when { $0.total }.returns(42)

        let sut: any MixedReturnService = stub()

        XCTAssertEqual(sut.name(), "MockName")
        XCTAssertEqual(sut.items(), ["a", "b", "c"])
        XCTAssertEqual(sut.total, 42)
    }

    func testCollectionWithMatchers() {
        let stub = RuntimeStub<any CollectionService>()

        stub.when { $0.fetchItems(query: any()) }.returns([1, 2])
        stub.when { $0.allTags() }.returns(["x"])
        stub.when { $0.count }.returns(5)

        let sut: any CollectionService = stub()

        XCTAssertEqual(sut.fetchItems(query: "anything"), [1, 2])
        XCTAssertEqual(sut.fetchItems(query: "other"), [1, 2])

        stub.verify(called: 2) { $0.fetchItems(query: any()) }
    }
}

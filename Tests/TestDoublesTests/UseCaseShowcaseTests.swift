import XCTest
import TestDoubles

// ============================================================================
// Showcase: What's now possible with swift-test-doubles
//
// Real-world mocking patterns demonstrating the full API surface.
// ============================================================================

struct PaymentDeclinedError: Error, Equatable { let reason: String }

final class UseCaseShowcaseTests: XCTestCase {

    // MARK: - 1. Repository — collections, search, multiple stubs

    func testUserRepository() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: 1) }.returns("Alice")
        stub.when { $0.find(id: 2) }.returns("Bob")
        stub.when { $0.find(id: any()) }.returns("Unknown")
        stub.when { $0.search(query: any()) }.returns(["Alice", "Bob"])
        stub.when { $0.count }.returns(2)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 1), "Alice")
        XCTAssertEqual(sut.find(id: 2), "Bob")
        XCTAssertEqual(sut.find(id: 999), "Unknown")
        XCTAssertEqual(sut.search(query: "a"), ["Alice", "Bob"])
        XCTAssertEqual(sut.count, 2)
    }

    // MARK: - 2. Throwing file service — happy path through throwing slots

    func testThrowingFileService_HappyPath() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("file contents")
        stub.when { try! $0.write(path: any(), content: any()) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()

        XCTAssertEqual(try sut.read(path: "/readme.txt"), "file contents")
        XCTAssertNoThrow(try sut.write(path: "/out.txt", content: "data"))
        XCTAssertTrue(sut.exists(at: "/readme.txt"))
        XCTAssertEqual(sut.basePath, "/mock")
    }

    // MARK: - 3. Dynamic answers — compute return from arguments

    func testDynamicAnswers() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: any()) }.answers { args in
            let id = args[0] as! Int
            return "User_\(id)"
        }
        stub.when { $0.search(query: any()) }.answers { args in
            let q = args[0] as! String
            return q.isEmpty ? [] : [q.uppercased()]
        }
        stub.when { $0.count }.returns(100)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 42), "User_42")
        XCTAssertEqual(sut.find(id: 7), "User_7")
        XCTAssertEqual(sut.search(query: "alice"), ["ALICE"])
        XCTAssertEqual(sut.search(query: ""), [])
    }

    // MARK: - 4. File service — throwing + verification

    func testFileService_ReadWriteVerify() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: "/a.txt") }.returns("aaa")
        stub.when { try $0.read(path: "/b.txt") }.returns("bbb")
        stub.when { try $0.read(path: any()) }.returns("default")
        stub.when { try! $0.write(path: any(), content: any()) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()

        XCTAssertEqual(try sut.read(path: "/a.txt"), "aaa")
        XCTAssertEqual(try sut.read(path: "/b.txt"), "bbb")
        XCTAssertEqual(try sut.read(path: "/c.txt"), "default")
        try! sut.write(path: "/out.txt", content: "data")

        stub.verify(called: 3) { try! $0.read(path: any()) }
        stub.verify(called: 1) { try! $0.write(path: any(), content: any()) }
    }

    // MARK: - 5. Argument inspection

    func testArgumentInspection() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.search(query: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        _ = sut.search(query: "alice")
        _ = sut.search(query: "bob")
        _ = sut.search(query: "alice")

        // Inspect what was actually passed
        stub.verify { $0.search(query: any()) }.withArgs { calls in
            XCTAssertEqual(calls.count, 3)
            XCTAssertEqual(calls[0][0] as! String, "alice")
            XCTAssertEqual(calls[1][0] as! String, "bob")
            XCTAssertEqual(calls[2][0] as! String, "alice")
        }
    }

    // MARK: - 6. Ordered verification

    func testOrderedVerification() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: any()) }.returns("X")
        stub.when { $0.search(query: any()) }.returns([])
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()

        // Find first, then search — order matters
        _ = sut.find(id: 1)
        _ = sut.search(query: "test")

        stub.verifyOrder {
            $0.find(id: any())
            $0.search(query: any())
        }
    }

    // MARK: - 7. Multiple independent mocks

    func testMultipleMocks() {
        let repoStub = RuntimeStub<any UserRepository>()
        let fileStub = RuntimeStub<any ThrowingFileService>()

        repoStub.when { $0.find(id: any()) }.returns("Alice")
        repoStub.when { $0.count }.returns(1)

        fileStub.when { try $0.read(path: any()) }.returns("data")
        fileStub.when { $0.exists(at: any()) }.returns(true)
        fileStub.when { $0.basePath }.returns("/tmp")

        let repo: any UserRepository = repoStub()
        let fs: any ThrowingFileService = fileStub()

        XCTAssertEqual(repo.find(id: 1), "Alice")
        XCTAssertEqual(try fs.read(path: "/test"), "data")
        XCTAssertTrue(fs.exists(at: "/test"))

        repoStub.verify(called: 1) { $0.find(id: any()) }
        fileStub.verify(called: 1) { try! $0.read(path: any()) }
    }

    // MARK: - 8. Predicate matching

    func testPredicateMatching() {
        let stub = RuntimeStub<any UserRepository>()

        stub.when { $0.find(id: match { $0 > 100 }) }.returns("VIP")
        stub.when { $0.find(id: match { $0 <= 100 }) }.returns("Regular")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()

        XCTAssertEqual(sut.find(id: 101), "VIP")
        XCTAssertEqual(sut.find(id: 50), "Regular")
        XCTAssertEqual(sut.find(id: 1), "Regular")
    }
}

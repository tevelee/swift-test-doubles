import XCTest
import TestDoubles

/// Throwing protocol tests — happy path through non-throwing thunks.
///
/// Non-throwing thunks serve throwing witness table slots correctly.
/// The mock returns stubbed values without throwing. Actual error
/// propagation requires the RuntimeCompiler (conforming type) approach.

final class ThrowingShowcaseTests: XCTestCase {

    func testThrowingService_HappyPath() {
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

    func testThrowingService_MultipleReadPaths() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: equal("/a")) }.returns("aaa")
        stub.when { try $0.read(path: equal("/b")) }.returns("bbb")
        stub.when { try $0.read(path: any()) }.returns("default")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        XCTAssertEqual(try sut.read(path: "/a"), "aaa")
        XCTAssertEqual(try sut.read(path: "/b"), "bbb")
        XCTAssertEqual(try sut.read(path: "/c"), "default")
    }

    func testThrowingService_Verification() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("x")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        _ = try? sut.read(path: "/a")
        _ = try? sut.read(path: "/b")
        _ = sut.exists(at: "/a")

        stub.verify(called: 2) { try $0.read(path: any()) }
        stub.verify(called: 1) { $0.exists(at: any()) }
        stub.verify(never: { try $0.write(path: any(), content: any()) })
    }
}

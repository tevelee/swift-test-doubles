import XCTest
import TestDoubles

/// Showcase: mocking throwing protocols with the RuntimeCompiler.
///
/// These tests exercise the full runtime compilation path:
/// 1. Auto-discover method signatures via dladdr
/// 2. Generate Swift source for a conforming mock type
/// 3. Compile to dylib with swiftc
/// 4. dlopen + find witness table via Echo
/// 5. Build existential → call methods → errors propagate
///
/// The protocols are defined in the TestDoubles module, so the
/// generated dylib can `import TestDoubles` to see them.

struct FileNotFoundError: Error, Equatable {
    let path: String
}

struct PermissionError: Error, Equatable {
    let reason: String
}

final class ThrowingShowcaseTests: XCTestCase {

    // MARK: - Happy path: throwing protocol, no errors

    func testThrowingService_HappyPath() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("file contents")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()

        XCTAssertEqual(try sut.read(path: "/readme.txt"), "file contents")
        XCTAssertEqual(sut.exists(at: "/readme.txt"), true)
        XCTAssertEqual(sut.basePath, "/mock")
    }

    // MARK: - Error path: mock actually throws

    func testThrowingService_ThrowsFileNotFound() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: "good.txt") }.returns("ok")
        stub.when { try $0.read(path: any()) }.throws(FileNotFoundError(path: "missing"))
        stub.when { $0.exists(at: any()) }.returns(false)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        // Happy path
        XCTAssertEqual(try sut.read(path: "good.txt"), "ok")

        // Error path: should throw
        XCTAssertThrowsError(try sut.read(path: "missing.txt")) { error in
            XCTAssertEqual(error as? FileNotFoundError, FileNotFoundError(path: "missing"))
        }

        XCTAssertFalse(sut.exists(at: "missing.txt"))
    }

    // MARK: - Multiple throwing methods

    func testThrowingService_WriteThrows() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("data")
        stub.when { try $0.write(path: any(), content: any()) }  // void, no error
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/tmp")

        let sut: any ThrowingFileService = stub()

        XCTAssertNoThrow(try sut.write(path: "/tmp/out", content: "hello"))
        XCTAssertEqual(try sut.read(path: "/tmp/out"), "data")
    }

    // MARK: - Dynamic error based on arguments

    func testThrowingService_DynamicError() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.answers { args in
            let path = args[0] as! String
            if path.hasPrefix("/private") {
                throw PermissionError(reason: "access denied")
            }
            return "contents of \(path)"
        }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        XCTAssertEqual(try sut.read(path: "/public/file"), "contents of /public/file")

        XCTAssertThrowsError(try sut.read(path: "/private/secret")) { error in
            XCTAssertEqual(error as? PermissionError, PermissionError(reason: "access denied"))
        }
    }

    // MARK: - Verify throwing calls

    func testThrowingService_Verification() {
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("x")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        _ = try? sut.read(path: "/a")
        _ = try? sut.read(path: "/b")
        _ = sut.exists(at: "/a")

        stub.verify(called: 2) { try! $0.read(path: any()) }
        stub.verify(called: 1) { $0.exists(at: any()) }
        stub.verify(never: { try! $0.write(path: any(), content: any()) })
    }
}

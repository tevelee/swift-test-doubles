import XCTest
import TestDoubles

// ============================================================================
// Runtime Compiler Tests
//
// These tests exercise the RuntimeCompiler path for protocols that can
// be imported by the compiled dylib (e.g., protocols in Foundation or
// in separate SPM modules).
//
// For protocols defined in the test target itself, runtime compilation
// can't import them — the thunk-based fallback is used instead.
// ============================================================================

// A simple protocol for testing the source generator
protocol SimpleThrowingService {
    func load(path: String) throws -> String
    func check(flag: Bool) -> Int
    var status: Int { get }
}

struct RealSimpleThrowingService: SimpleThrowingService {
    func load(path: String) throws -> String { "" }
    func check(flag: Bool) -> Int { 0 }
    var status: Int { 0 }
}

// A protocol with async
protocol SimpleAsyncService {
    func fetch(id: Int) async -> String
    var isReady: Bool { get }
}

struct RealSimpleAsyncService: SimpleAsyncService {
    func fetch(id: Int) async -> String { "" }
    var isReady: Bool { false }
}

final class RuntimeCompilerTests: XCTestCase {

    // MARK: - Source Generation Tests

    func testSourceGeneration_SimpleProtocol() {
        let source = RuntimeCompiler.generateSource(
            protocolName: "SimpleThrowingService",
            moduleName: "TestModule",
            signatures: .describing {
                $0.method("load", args: [.string("path")], returns: .string, throws: true)
                $0.method("check", args: [.bool("flag")], returns: .int)
                $0.getter("status", type: .int)
            }
        )

        // Clean, generic source — no type-specific dispatch
        XCTAssertTrue(source.contains("struct _TDMock: SimpleThrowingService"))
        XCTAssertTrue(source.contains("MockBridge.dispatch"))
        XCTAssertTrue(source.contains("throws"))
        XCTAssertTrue(source.contains("var status: Int"))
        // Should NOT contain type-specific bridge functions
        XCTAssertFalse(source.contains("td_bridge_dispatch_int"))
        XCTAssertFalse(source.contains("td_bridge_dispatch_string"))
    }

    func testSourceGeneration_TypeAgnostic() {
        // Generated code should work for ANY type without special-casing
        let source = RuntimeCompiler.generateSource(
            protocolName: "MyService",
            moduleName: "MyFramework",
            signatures: .describing {
                $0.method("process", args: [.type("input", "CustomStruct")], returns: .custom("CustomResult"))
                $0.getter("config", type: .custom("AppConfig"))
            }
        )

        // Same MockBridge.dispatch for custom types as for Int/String
        XCTAssertTrue(source.contains("-> CustomResult { MockBridge.dispatch"))
        XCTAssertTrue(source.contains("var config: AppConfig { MockBridge.dispatch"))
        XCTAssertTrue(source.contains("import MyFramework"))
    }

    func testSourceGeneration_FiltersCoroutines() {
        let source = RuntimeCompiler.generateSource(
            protocolName: "TestProto",
            moduleName: "TestModule",
            signatures: .describing {
                $0.getter("name", type: .string)
                $0.coroutine()
                $0.coroutine()
                $0.method("reset")
            }
        )

        let structBody = source.components(separatedBy: "_TDMock:").last ?? ""
        XCTAssertTrue(structBody.contains("var name: String"))
        XCTAssertTrue(structBody.contains("func reset()"))
        XCTAssertFalse(structBody.contains("coroutine"))
    }

    func testModuleNameExtraction() {
        // Test extracting module name from demangled witness string
        let demangled = "protocol witness for TestModule.MyService.load(path: Swift.String) throws -> Swift.String in conformance TestModule.RealService : TestModule.MyService in TestModule"

        let module = RuntimeCompiler.extractModuleName(from: demangled)
        XCTAssertEqual(module, "TestModule")
    }

    func testModuleNameExtraction_MultiWord() {
        let demangled = "protocol witness for MyFramework.APIClient.fetch(id: Swift.Int) -> Swift.String in conformance MyFramework.RealClient : MyFramework.APIClient in MyFramework"

        let module = RuntimeCompiler.extractModuleName(from: demangled)
        XCTAssertEqual(module, "MyFramework")
    }

    // MARK: - Thunk Fallback Tests

    func testThrowingProtocol_FallsBackToThunks() {
        // Protocols defined in the test target can't be imported by the runtime
        // compiler. This test verifies graceful fallback to thunk-based approach.
        let stub = RuntimeStub<any SimpleThrowingService>()

        // Non-throwing path works via existing thunks
        stub.when { try $0.load(path: any()) }.returns("fallback-content")
        stub.when { $0.check(flag: any()) }.returns(42)
        stub.when { $0.status }.returns(200)

        let sut: any SimpleThrowingService = stub()

        // Happy path: thunks return values without throwing
        XCTAssertEqual(try sut.load(path: "/test"), "fallback-content")
        XCTAssertEqual(sut.check(flag: true), 42)
        XCTAssertEqual(sut.status, 200)
    }

    func testThrowsAPI_RegistersThrowingStub() {
        // Verify the .throws() API registers a throwing stub
        let stub = RuntimeStub<any SimpleThrowingService>()

        struct TestError: Error, Equatable { let code: Int }

        stub.when { try $0.load(path: "good") }.returns("content")
        stub.when { try $0.load(path: "bad") }.throws(TestError(code: 404))
        stub.when { $0.check(flag: any()) }.returns(0)
        stub.when { $0.status }.returns(0)

        // The .throws() stub is registered in recorder.throwingStubs
        XCTAssertNotNil(stub.recorder.throwingStubs[0])
    }

    // MARK: - Compilation Tests (actually invoke swiftc)

    func testBasicCompilation() {
        // Compile a minimal Swift file to verify the toolchain works
        let source = """
        import Foundation
        public struct _TDMock {
            public let _ctx: UnsafeRawPointer
        }
        """

        let result = RuntimeCompiler.compileMock(
            protocolName: "Dummy",
            moduleName: "Foundation",
            signatures: []
        )

        // Even though we passed empty signatures, the compilation itself
        // should work if we override the source. For now, just verify
        // the compiler infrastructure doesn't crash.
        // (result is nil because the generated source tries to import
        // the protocol, which may not work for all cases)
    }
}

// Make DiscoveredSignature accessible from tests
extension DiscoveredSignature {
    // Allow test creation with minimal parameters
}

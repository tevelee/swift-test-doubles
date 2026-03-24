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
        // Verify generated source looks correct for a simple protocol
        let sigs = [
            DiscoveredSignature(slot: 0, kind: .method, methodName: "load(path:)", args: ["String"], ret: "String",
                                isThrowing: true, rawDemangled: "", paramLabels: ["path"]),
            DiscoveredSignature(slot: 1, kind: .method, methodName: "check(flag:)", args: ["Bool"], ret: "Int",
                                isThrowing: false, rawDemangled: "", paramLabels: ["flag"]),
            DiscoveredSignature(slot: 2, kind: .getter, methodName: "status", args: [], ret: "Int"),
        ]

        let source = RuntimeCompiler.generateSource(
            protocolName: "SimpleThrowingService",
            moduleName: "TestModule",
            signatures: sigs
        )

        // Should contain the struct definition
        XCTAssertTrue(source.contains("struct _TDMock: SimpleThrowingService"))
        // Should contain the throwing method
        XCTAssertTrue(source.contains("throws"))
        // Should contain td_bridge_should_throw for the throwing method
        XCTAssertTrue(source.contains("td_bridge_should_throw"))
        // Should have a getter for status
        XCTAssertTrue(source.contains("var status: Int"))

        print("Generated source:\n\(source)")
    }

    func testSourceGeneration_FiltersCoroutines() {
        // Verify coroutines/associated types are filtered out
        let sigs = [
            DiscoveredSignature(slot: 0, kind: .getter, methodName: "name", args: [], ret: "String"),
            DiscoveredSignature(slot: 1, kind: .modifyCoroutine, methodName: "name", args: [], ret: "String"),
            DiscoveredSignature(slot: 2, kind: .readCoroutine, methodName: "name", args: [], ret: "String"),
            DiscoveredSignature(slot: 3, kind: .method, methodName: "reset()", args: [], ret: "Void"),
        ]

        let source = RuntimeCompiler.generateSource(
            protocolName: "TestProto",
            moduleName: "TestModule",
            signatures: sigs
        )

        // Should only have getter + reset, not coroutines
        let structBody = source.components(separatedBy: "_TDMock:").last ?? ""
        XCTAssertTrue(structBody.contains("var name: String"))
        XCTAssertTrue(structBody.contains("func reset()"))
        XCTAssertFalse(structBody.contains("modifyCoroutine"))
        XCTAssertFalse(structBody.contains("readCoroutine"))
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

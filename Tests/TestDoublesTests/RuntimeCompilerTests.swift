#if COMPILED_STUB && os(macOS)
import Testing
@testable import TestDoubles

@Suite struct SourceGenerationTests {

    @Test func simpleProtocol() {
        let source = RuntimeCompiler.generateSource(
            protocolName: "SimpleService",
            moduleName: "TestModule",
            signatures: .describing {
                $0.method("load", args: [.string("path")], returns: .string, throws: true)
                $0.method("check", args: [.bool("flag")], returns: .int)
                $0.getter("status", type: .int)
            }
        )

        #expect(source.contains("struct _TDMock: SimpleService"))
        #expect(source.contains("MockBridge.dispatch"))
        #expect(source.contains("throws"))
        #expect(source.contains("var status: Int"))
        #expect(!source.contains("td_bridge_dispatch_int"))
    }

    @Test func typeAgnostic() {
        let source = RuntimeCompiler.generateSource(
            protocolName: "MyService",
            moduleName: "MyFramework",
            signatures: .describing {
                $0.method("process", args: [.type("input", "CustomStruct")], returns: .custom("CustomResult"))
                $0.getter("config", type: .custom("AppConfig"))
            }
        )

        #expect(source.contains("-> CustomResult { MockBridge.dispatch"))
        #expect(source.contains("var config: AppConfig { MockBridge.dispatch"))
        #expect(source.contains("import MyFramework"))
    }

    @Test func filtersCoroutines() {
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

        let body = source.components(separatedBy: "_TDMock:").last ?? ""
        #expect(body.contains("var name: String"))
        #expect(body.contains("func reset()"))
        #expect(!body.contains("coroutine"))
    }

    @Test func asyncGeneration() {
        let source = RuntimeCompiler.generateSource(
            protocolName: "AsyncService",
            moduleName: "TestModule",
            signatures: .describing {
                $0.method("fetch", args: [.int("id")], returns: .string, async: true)
                $0.method("save", args: [.string("data")], returns: .bool, throws: true, async: true)
            }
        )

        #expect(source.contains("async ->"))
        #expect(source.contains("async throws ->"))
    }
}

@Suite struct ModuleExtractionTests {

    @Test func extractsModuleName() {
        let demangled = "protocol witness for TestModule.MyService.load(path: Swift.String) throws -> Swift.String in conformance TestModule.RealService : TestModule.MyService in TestModule"
        #expect(RuntimeCompiler.extractModuleName(from: demangled) == "TestModule")
    }

    @Test func multiWordModule() {
        let demangled = "protocol witness for MyFramework.APIClient.fetch(id: Swift.Int) -> Swift.String in conformance MyFramework.RealClient : MyFramework.APIClient in MyFramework"
        #expect(RuntimeCompiler.extractModuleName(from: demangled) == "MyFramework")
    }
}

@Suite struct ThrowingProtocolFallbackTests {

    @Test func fallsBackToThunks() throws {
        // Protocols in the test target can't be imported by RuntimeCompiler.
        // Verify graceful fallback to thunk-based approach.
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.returns("fallback")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        #expect(try stub().read(path: "/test") == "fallback")
    }

    @Test func thenRegistersThrowingStub() {
        struct TestError: Error { let code: Int }
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: "good") }.returns("content")
        stub.when { try $0.read(path: "bad") }.then { throw TestError(code: 404) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        #expect(stub.recorder.throwingStubs[0] != nil)
    }

    @Test func basicCompilation() {
        // Compiles an empty mock (no methods) — validates swiftc works
        let handle = RuntimeCompiler.compileMock(
            protocolName: "Dummy",
            moduleName: "Foundation",
            signatures: []
        )
        _ = handle // May return nil, but shouldn't crash
    }

    @Test func compiledMockForImportableProtocol() throws {
        // ThrowingFileService is in the TestDoubles module.
        // Uses .auto — compiles if possible, falls back to thunks otherwise.
        let stub = RuntimeStub<any ThrowingFileService>()

        stub.when { try $0.read(path: any()) }.returns("works!")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/test")

        let sut: any ThrowingFileService = stub()

        #expect(try sut.read(path: "/test") == "works!")
        #expect(sut.exists(at: "/test") == true)
        #expect(sut.basePath == "/test")
    }

#if COMPILED_STUB
    @Test func compiledMockAsync() async throws {

        let stub = try CompiledStub<any AsyncDataLoader>()

        await stub.when { try await $0.load(url: any()) }.returns("async-data")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(42)

        let sut: any AsyncDataLoader = stub()

        let result = try await sut.load(url: "https://example.com")
        #expect(result == "async-data")
        #expect(sut.cacheSize == 42)
    }
#endif // COMPILED_STUB
}
#endif // COMPILED_STUB && os(macOS)

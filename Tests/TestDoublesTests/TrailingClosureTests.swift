#if RUNTIME_STUB
import Testing
@testable import TestDoubles

@Suite struct TrailingClosureTests {

    @Test func staticValue() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) } then: { "Alice" }
        stub.when { $0.count } then: { 42 }
        
        let sut: any UserRepository = stub()
        #expect(sut.find(id: 1) == "Alice")
        #expect(sut.count == 42)
    }

    @Test func dynamicWithArgs() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) } then: { args in "user_\(args[0])" }
        stub.when { $0.count } then: { 0 }

        #expect(stub().find(id: 42) == "user_42")
    }

    @Test func throwingHappyPath() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) } then: { "content" }
        stub.when { $0.exists(at: any()) } then: { true }
        stub.when { $0.basePath } then: { "/mock" }

        let sut: any ThrowingFileService = stub()
        #expect(try sut.read(path: "/x") == "content")
        #expect(sut.basePath == "/mock")
    }

    @Test func voidMethodStillWorks() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.find(id: any()) } then: { "X" }
        stub.when { $0.count } then: { 0 }

        let sut: any UserRepository = stub()
        _ = sut.find(id: 1)
        stub.verify(called: 1) { $0.find(id: any()) }
    }

    @Test func collectionReturn() {
        let stub = RuntimeStub<any UserRepository>()
        stub.when { $0.search(query: any()) } then: { ["a", "b", "c"] }
        stub.when { $0.count } then: { 3 }

        #expect(stub().search(query: "x") == ["a", "b", "c"])
    }

    #if COMPILED_STUB
    @Test func asyncCompiledMock() async throws {
        let stub = try CompiledStub<any AsyncDataLoader>()
        await stub.when { try await $0.load(url: any()) }.returns("async!")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(99)

        let sut: any AsyncDataLoader = stub()
        #expect(try await sut.load(url: "https://x.com") == "async!")
        #expect(sut.cacheSize == 99)
    }
    #endif

    @Test func mixTrailingAndChained() {
        let stub = RuntimeStub<any UserRepository>()
        // Trailing closure style
        stub.when { $0.find(id: equal(1)) } then: { "Alice" }
        // Chained style
        stub.when { $0.find(id: any()) }.returns("Unknown")
        stub.when { $0.count }.returns(0)

        let sut: any UserRepository = stub()
        #expect(sut.find(id: 1) == "Alice")
        #expect(sut.find(id: 99) == "Unknown")
    }
}
#endif // RUNTIME_STUB

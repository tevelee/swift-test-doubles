#if RUNTIME_STUB
import Testing
@testable import TestDoubles
import TestDoublesFixtures

// Protocols for testing (defined locally — not importable by RuntimeCompiler)

protocol Calculator {
    func add(_ a: Int, _ b: Int) -> Int
    func describe(_ value: Int) -> String
    var precision: Int { get }
}
struct RealCalculator: Calculator {
    func add(_ a: Int, _ b: Int) -> Int { a + b }
    func describe(_ value: Int) -> String { "\(value)" }
    var precision: Int { 10 }
}

protocol Settings {
    var theme: String { get set }
    var fontSize: Int { get }
    func reset()
    func apply(key: String)
}
struct RealSettings: Settings {
    var theme = "light"
    var fontSize: Int { 14 }
    func reset() {}
    func apply(key: String) {}
}

protocol TagStore {
    func tags(for category: String) -> [String]
    func allCategories() -> [String]
    func tagCount(in category: String) -> Int
    var isEmpty: Bool { get }
}
struct RealTagStore: TagStore {
    func tags(for category: String) -> [String] { [] }
    func allCategories() -> [String] { [] }
    func tagCount(in category: String) -> Int { 0 }
    var isEmpty: Bool { true }
}

protocol AppConfig {
    var appName: String { get }
    var version: Int { get }
    var isDebug: Bool { get }
    var scale: Double { get }
}
struct RealAppConfig: AppConfig {
    var appName: String { "" }
    var version: Int { 0 }
    var isDebug: Bool { false }
    var scale: Double { 1.0 }
}

protocol FileLoader {
    func load(path: String) throws -> String
    func exists(path: String) -> Bool
}
struct RealFileLoader: FileLoader {
    func load(path: String) throws -> String { "" }
    func exists(path: String) -> Bool { false }
}

// MARK: - Core Stubbing

@Suite struct ZeroConfigTests {

    @Test func exactMatching() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.add(1, 2) }.returns(42)
        stub.when { $0.describe(99) }.returns("ninety-nine")
        stub.when { $0.precision }.returns(5)

        let sut: any Calculator = stub()

        #expect(sut.add(1, 2) == 42)
        #expect(sut.describe(99) == "ninety-nine")
        #expect(sut.precision == 5)
    }

    @Test func freeMatchers() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.add(any(), any()) }.returns(100)
        stub.when { $0.describe(any()) }.returns("anything")
        stub.when { $0.precision }.returns(1)

        let sut: any Calculator = stub()

        #expect(sut.add(5, 10) == 100)
        #expect(sut.describe(42) == "anything")
    }

    @Test func predicateMatchers() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any(where: { $0 > 100 })) }.returns("VIP")
        stub.when { $0.describe(any(where: { $0 <= 100 })) }.returns("Regular")
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()

        #expect(sut.describe(101) == "VIP")
        #expect(sut.describe(50) == "Regular")
    }

    @Test func dynamicAnswers() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any()) }.then { args in
            let id = args[0] as! Int
            return "User_\(id)"
        }
        stub.when { $0.precision }.returns(42)

        let sut: any Calculator = stub()

        #expect(sut.describe(7) == "User_7")
        #expect(sut.describe(99) == "User_99")
    }

    @Test func bestMatchBySpecificity() {
        let stub = RuntimeStub<any Calculator>()
        // Registration order doesn't matter — specificity wins
        stub.when { $0.describe(any()) }.returns("default")
        stub.when { $0.describe(equal(42)) }.returns("the answer")
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()

        #expect(sut.describe(42) == "the answer")
        #expect(sut.describe(99) == "default")
    }
}

// MARK: - Verification

@Suite struct VerificationTests {

    @Test func callCounts() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any()) }.returns("X")
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()
        _ = sut.describe(1)
        _ = sut.describe(2)
        _ = sut.describe(3)
        _ = sut.precision

        stub.verify(called: 3) { $0.describe(any()) }
        stub.verify(called: 1) { $0.precision }
        stub.verify(never: { $0.add(any(), any()) })
    }

    @Test func builderStyle() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.add(any(), any()) }.returns(0)
        stub.when { $0.precision }.returns(0)

        _ = stub().add(1, 2)

        stub.verify { $0.add(1, 2) }.wasCalled()
        stub.verify { $0.add(any(), any()) }.wasCalled(times: 1)
    }

    @Test func argumentInspection() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any()) }.returns("X")
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()
        _ = sut.describe(42)
        _ = sut.describe(99)

        stub.verify { $0.describe(any()) }.withArgs { calls in
            #expect(calls.count == 2)
            #expect(calls[0][0] as! Int == 42)
            #expect(calls[1][0] as! Int == 99)
        }
    }

    @Test func orderedVerification() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any()) }.returns("X")
        stub.when { $0.add(any(), any()) }.returns(0)
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()
        _ = sut.describe(1)
        _ = sut.add(2, 3)

        stub.verifyOrder {
            _ = $0.describe(any())
            _ = $0.add(any(), any())
        }
    }

    @Test func orderedVerificationDoesNotReplayStubbedHandlers() {
        let stub = RuntimeStub<any Calculator>()
        var describeExecutions = 0
        stub.when { $0.describe(any()) }.then { _ in
            describeExecutions += 1
            return "X"
        }

        let sut: any Calculator = stub()
        _ = sut.describe(1)

        #expect(describeExecutions == 1)
        stub.verifyOrder {
            _ = $0.describe(any())
        }
        #expect(describeExecutions == 1)
    }

    @Test func callLog() {
        let stub = RuntimeStub<any Calculator>()
        stub.when { $0.describe(any()) }.returns("X")
        stub.when { $0.precision }.returns(0)

        let sut: any Calculator = stub()
        _ = sut.describe(1)
        _ = sut.describe(2)
        _ = sut.precision

        #expect(stub.calls.count == 3)
    }
}

// MARK: - Getters, Setters, Void

@Suite struct PropertyAndVoidTests {

    @Test func multipleGetterTypes() {
        let stub = RuntimeStub<any AppConfig>()
        stub.when { $0.appName }.returns("TestApp")
        stub.when { $0.version }.returns(42)
        stub.when { $0.isDebug }.returns(true)
        stub.when { $0.scale }.returns(2.0)

        let sut: any AppConfig = stub()

        #expect(sut.appName == "TestApp")
        #expect(sut.version == 42)
        #expect(sut.isDebug == true)
        #expect(sut.scale == 2.0)
    }

    @Test func settersAndVoidMethods() {
        let stub = RuntimeStub<any Settings>()
        stub.when { $0.theme }.returns("dark")
        stub.when { $0.fontSize }.returns(16)
        stub.when(setting: { $0.theme = "light" })
        stub.when { $0.reset() }
        stub.when { $0.apply(key: any()) }

        let sut: any Settings = stub()
        #expect(sut.theme == "dark")
        #expect(sut.fontSize == 16)

        var mutable: any Settings = stub()
        mutable.theme = "light"
        sut.reset()
        sut.apply(key: "color")

        stub.verify(setting: { $0.theme = "light" }).wasCalled()
        stub.verify { $0.reset() }.wasCalled(times: 1)
    }

    @Test func collectionReturns() {
        let stub = RuntimeStub<any TagStore>()
        stub.when { $0.tags(for: "swift") }.returns(["concurrency", "macros"])
        stub.when { $0.tags(for: any()) }.returns([])
        stub.when { $0.allCategories() }.returns(["swift", "rust"])
        stub.when { $0.tagCount(in: any()) }.returns(5)
        stub.when { $0.isEmpty }.returns(false)

        let sut: any TagStore = stub()

        #expect(sut.tags(for: "swift") == ["concurrency", "macros"])
        #expect(sut.tags(for: "unknown") == [])
        #expect(sut.allCategories() == ["swift", "rust"])
    }
}

// MARK: - Throwing

@Suite struct ThrowingTests {

    @Test func happyPath() throws {
        let stub = RuntimeStub<any FileLoader>()
        stub.when { try $0.load(path: any()) }.returns("content")
        stub.when { $0.exists(path: any()) }.returns(true)

        let sut: any FileLoader = stub()

        #expect(try sut.load(path: "/test") == "content")
        #expect(sut.exists(path: "/test") == true)
    }

    @Test func throwingHappyPathFileService() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.returns("file contents")
        stub.when { try $0.write(path: any(), content: any()) }
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/mock")

        let sut: any ThrowingFileService = stub()

        #expect(try sut.read(path: "/readme.txt") == "file contents")
        #expect(throws: Never.self) { try sut.write(path: "/out.txt", content: "data") }
        #expect(sut.basePath == "/mock")
    }

    @Test func throwingVerification() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: any()) }.returns("x")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()
        _ = try? sut.read(path: "/a")
        _ = try? sut.read(path: "/b")

        stub.verify(called: 2) { try $0.read(path: any()) }
        stub.verify(never: { try $0.write(path: any(), content: any()) })
    }

    @Test func throwingVerificationDoesNotReplayStubbedHandlers() throws {
        let stub = RuntimeStub<any FileLoader>()
        var loadExecutions = 0
        stub.when { try $0.load(path: any()) }.then { _ in
            loadExecutions += 1
            return "content"
        }

        let sut: any FileLoader = stub()
        #expect(try sut.load(path: "/a") == "content")

        #expect(loadExecutions == 1)
        stub.verify { try $0.load(path: any()) }.wasCalled()
        #expect(loadExecutions == 1)
    }

    @Test func throwingMultiplePaths() throws {
        let stub = RuntimeStub<any ThrowingFileService>()
        stub.when { try $0.read(path: equal("/a")) }.returns("aaa")
        stub.when { try $0.read(path: equal("/b")) }.returns("bbb")
        stub.when { try $0.read(path: any()) }.returns("default")
        stub.when { $0.exists(at: any()) }.returns(true)
        stub.when { $0.basePath }.returns("/")

        let sut: any ThrowingFileService = stub()

        #expect(try sut.read(path: "/a") == "aaa")
        #expect(try sut.read(path: "/b") == "bbb")
        #expect(try sut.read(path: "/c") == "default")
    }
}

// MARK: - Slot-Based Init

@Suite struct SlotBasedTests {

    @Test func typedMethodReferences() {
        let real: any Calculator = RealCalculator()
        let stub = RuntimeStub<any Calculator>(
            .from(real.add),
            .from(real.describe),
            .getter(real.precision)
        )

        stub.when { $0.add(any(), any()) }.returns(99)
        stub.when { $0.describe(any()) }.returns("typed")
        stub.when { $0.precision }.returns(7)

        let sut: any Calculator = stub()

        #expect(sut.add(1, 2) == 99)
        #expect(sut.describe(1) == "typed")
        #expect(sut.precision == 7)
    }

    @Test func throwingMethodReferences() throws {
        let real: any FileLoader = RealFileLoader()
        let stub = RuntimeStub<any FileLoader>(
            .from(real.load),
            .from(real.exists)
        )

        stub.when { try $0.load(path: any()) }.returns("typed-content")
        stub.when { $0.exists(path: any()) }.returns(false)

        let sut: any FileLoader = stub()

        #expect(try sut.load(path: "/x") == "typed-content")
        #expect(sut.exists(path: "/x") == false)
    }

    @Test func asyncMethodReferences() async throws {
        let real: any AsyncDataLoader = RealDataLoader()
        let stub = RuntimeStub<any AsyncDataLoader>(
            .from(real.load),
            .from(real.prefetch),
            .getter(real.cacheSize)
        )

        await stub.when { try await $0.load(url: any()) }.returns("typed-async")
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(8)

        let sut: any AsyncDataLoader = stub()

        #expect(try await sut.load(url: "/x") == "typed-async")
        #expect(sut.cacheSize == 8)
    }
}

// MARK: - Multiple Stubs

@Suite struct MultiStubTests {

    @Test func independentStubs() {
        let calcStub = RuntimeStub<any Calculator>()
        let configStub = RuntimeStub<any AppConfig>()

        calcStub.when { $0.describe(any()) }.returns("User")
        calcStub.when { $0.precision }.returns(10)

        configStub.when { $0.appName }.returns("Test")
        configStub.when { $0.version }.returns(1)
        configStub.when { $0.isDebug }.returns(false)
        configStub.when { $0.scale }.returns(1.0)

        #expect(calcStub().describe(1) == "User")
        #expect(configStub().appName == "Test")
    }
}
#endif // RUNTIME_STUB

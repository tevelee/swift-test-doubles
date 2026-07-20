import Testing
import TestDoubles
import TestDoublesFixtures

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
    var theme: String { get }
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
    var scale: Double { 1 }
}

protocol FileLoader {
    func load(path: String) throws -> String
    func exists(path: String) -> Bool
}

struct RealFileLoader: FileLoader {
    func load(path: String) throws -> String { "" }
    func exists(path: String) -> Bool { false }
}

@Suite struct StubbingTests {
    @Test func exactAndWildcardMatching() throws {
        let stub = try Stub<any Calculator>()
        stub.when { $0.add(1, 2) }.thenReturn(42)
        stub.when { $0.add(any(), any()) }.thenReturn(-1)
        stub.when { $0.describe(any()) }.thenReturn("anything")
        stub.when { $0.precision }.thenReturn(5)

        let calculator: any Calculator = stub()
        #expect(calculator.add(1, 2) == 42)
        #expect(calculator.add(3, 4) == -1)
        #expect(calculator.describe(99) == "anything")
        #expect(calculator.precision == 5)
    }

    @Test func typedDynamicHandlerReceivesArguments() throws {
        let stub = try Stub<any Calculator>()
        stub.when { $0.add(any(), any()) }.then { (lhs: Int, rhs: Int) in
            lhs * rhs
        }
        stub.when { $0.describe(any()) }.then { (value: Int) in
            "value:\(value)"
        }

        let calculator: any Calculator = stub()
        #expect(calculator.add(6, 7) == 42)
        #expect(calculator.describe(9) == "value:9")
    }

    @Test func independentStubsDoNotShareState() throws {
        let first = try Stub<any Calculator>()
        let second = try Stub<any Calculator>()
        first.when { $0.precision }.thenReturn(1)
        second.when { $0.precision }.thenReturn(2)

        #expect(first().precision == 1)
        #expect(second().precision == 2)
    }
}

@Suite struct DirectVerificationTests {
    @Test func verifiesDefaultExactAndNeverCounts() throws {
        let stub = try Stub<any Calculator>()
        stub.when { $0.describe(any()) }.thenReturn("X")

        let calculator: any Calculator = stub()
        _ = calculator.describe(1)
        _ = calculator.describe(2)

        stub.verify { $0.describe(any()) }
        stub.verify(.exactly(2)) { $0.describe(any()) }
        stub.verify(.never()) { $0.add(any(), any()) }

        stub.verify(2...) { $0.describe(any()) }
        stub.verify(...2) { $0.describe(any()) }
        stub.verify(1 ... 2) { $0.describe(any()) }
        stub.verify(0 ..< 3) { $0.describe(any()) }
    }

    @Test func verificationDoesNotReplayHandler() throws {
        let stub = try Stub<any Calculator>()
        let executions = LockedCounter()
        stub.when { $0.describe(any()) }.then { (value: Int) in
            executions.increment()
            return "\(value)"
        }

        _ = stub().describe(1)
        stub.verify { $0.describe(any()) }
        #expect(executions.value == 1)
    }
}

@Suite struct PropertyAndVoidTests {
    @Test func gettersAcrossReturnShapes() throws {
        let stub = try Stub<any AppConfig>()
        stub.when { $0.appName }.thenReturn("TestApp")
        stub.when { $0.version }.thenReturn(42)
        stub.when { $0.isDebug }.thenReturn(true)
        stub.when { $0.scale }.thenReturn(2.5)

        let config: any AppConfig = stub()
        #expect(config.appName == "TestApp")
        #expect(config.version == 42)
        #expect(config.isDebug)
        #expect(config.scale == 2.5)
    }

    @Test func gettersAndExplicitVoidBehaviors() throws {
        let stub = try Stub<any Settings>()
        stub.when { $0.theme }.thenReturn("dark")
        stub.when { $0.fontSize }.thenReturn(16)
        stub.when { $0.reset() }.thenDoNothing()
        stub.when { $0.apply(key: any()) }.thenDoNothing()

        let settings: any Settings = stub()
        #expect(settings.theme == "dark")
        settings.reset()
        settings.apply(key: "color")

        stub.verify(.exactly(1)) { $0.reset() }
        stub.verify(.exactly(1)) { $0.apply(key: "color") }
    }
}

@Suite struct ThrowingTests {
    @Test func throwingHandlerReturnsAndPropagatesErrors() throws {
        struct ReadError: Error, Equatable { let path: String }

        let stub = try Stub<any FileLoader>()
        stub.when { try $0.load(path: equal("/missing")) }
            .thenThrow(ReadError(path: "/missing"))
        stub.when { try $0.load(path: any()) }.then { (path: String) in "contents:\(path)" }
        stub.when { $0.exists(path: any()) }.thenReturn(true)

        let loader: any FileLoader = stub()
        #expect(try loader.load(path: "/readme") == "contents:/readme")
        let error = #expect(throws: ReadError.self) {
            try loader.load(path: "/missing")
        }
        #expect(error?.path == "/missing")

        stub.verify(.exactly(2)) { try $0.load(path: any()) }
        stub.verify(.never()) { $0.exists(path: equal("/missing")) }
    }

    @Test func throwingVoidRequirementCanExplicitlyDoNothing() throws {
        let stub = try Stub<any ThrowingFileService>()
        stub.when { try $0.write(path: any(), content: any()) }.thenDoNothing()

        try stub().write(path: "/out", content: "data")
        stub.verify { try $0.write(path: "/out", content: "data") }
    }
}

@Suite struct ExplicitRequirementTests {
    @Test func buildsWithoutARealConformer() throws {
        let stub = try Stub<any PrototypeCalculator>(
            .method(Int.self, Int.self, returning: Int.self),
            .method(Int.self, returning: String.self),
            .getter(Int.self)
        )
        stub.when { $0.add(any(), any()) }.then { (a: Int, b: Int) in a + b }
        stub.when { $0.describe(any()) }.then { (value: Int) in "\(value)" }
        stub.when { $0.precision }.thenReturn(12)

        let calculator: any PrototypeCalculator = stub()
        #expect(calculator.add(2, 4) == 6)
        #expect(calculator.describe(6) == "6")
        #expect(calculator.precision == 12)
    }

    @Test func preservesThrowingAndAsyncEffects() async throws {
        let stub = try Stub<any AsyncDataLoader>(
            .method(String.self, returning: String.self, isThrowing: true, isAsync: true),
            .method([String].self, returning: Void.self, isAsync: true),
            .getter(Int.self)
        )
        await stub.when { try await $0.load(url: any()) }.thenReturn("data")
        await stub.when { await $0.prefetch(urls: any()) }.thenDoNothing()
        stub.when { $0.cacheSize }.thenReturn(3)

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "url") == "data")
        await loader.prefetch(urls: ["one"])
        #expect(loader.cacheSize == 3)
    }
}

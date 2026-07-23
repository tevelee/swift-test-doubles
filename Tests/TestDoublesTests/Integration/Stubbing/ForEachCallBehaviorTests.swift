import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol ForEachCallLoader: Sendable {
    func loadFeed() throws -> [String]
    func fetch(page: Int) async throws -> [String]
    func value(for key: String) -> Int
}

struct RealForEachCallLoader: ForEachCallLoader {
    func loadFeed() throws -> [String] { [] }
    func fetch(page: Int) async throws -> [String] { [] }
    func value(for key: String) -> Int { 0 }
}

private enum ForEachCallError: Error, Equatable {
    case timeout
}

@Suite struct ForEachCallBehaviorTests {
    @Test func failsTwiceThenRecoversByCall() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { try $0.loadFeed() }.thenForEachCall { (attempt: Int) in
            if attempt < 3 { throw ForEachCallError.timeout }
            return ["Hello, world"]
        }

        let feed: any ForEachCallLoader = loader()
        #expect(throws: ForEachCallError.timeout) { try feed.loadFeed() }
        #expect(throws: ForEachCallError.timeout) { try feed.loadFeed() }
        #expect(try feed.loadFeed() == ["Hello, world"])

        loader.verify(.exactly(3)) { try $0.loadFeed() }
    }

    @Test func passesBothCountAndTypedArguments() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { $0.value(for: any()) }.thenForEachCall { (count: Int, key: String) in
            count * 100 + key.count
        }

        let sut: any ForEachCallLoader = loader()
        #expect(sut.value(for: "ab") == 102)
        #expect(sut.value(for: "abc") == 203)
    }

    @Test func omittingTrailingArgumentsCountsOnly() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { $0.value(for: any()) }.thenForEachCall { (count: Int) in count }

        let sut: any ForEachCallLoader = loader()
        #expect(sut.value(for: "irrelevant") == 1)
        #expect(sut.value(for: "irrelevant") == 2)
        #expect(sut.value(for: "irrelevant") == 3)
    }

    @Test func countIsScopedPerRegistration() throws {
        let loader = try Stub<any ForEachCallLoader>()
        loader.when { $0.value(for: equal("a")) }.thenForEachCall { (count: Int) in count }
        loader.when { $0.value(for: any()) }.thenForEachCall { (count: Int) in 100 + count }

        let sut: any ForEachCallLoader = loader()
        // The specific registration and the fallback advance independently.
        #expect(sut.value(for: "a") == 1)
        #expect(sut.value(for: "b") == 101)
        #expect(sut.value(for: "a") == 2)
        #expect(sut.value(for: "b") == 102)
    }

    @Test func supportsAsyncRequirements() async throws {
        let loader = try Stub<any ForEachCallLoader>()
        await loader.when { try await $0.fetch(page: any()) }
            .thenForEachCall { (attempt: Int, page: Int) in
                await Task.yield()
                if attempt == 1 { throw ForEachCallError.timeout }
                return ["page-\(page)"]
            }

        let sut: any ForEachCallLoader = loader()
        await #expect(throws: ForEachCallError.timeout) { try await sut.fetch(page: 7) }
        #expect(try await sut.fetch(page: 7) == ["page-7"])
    }
}

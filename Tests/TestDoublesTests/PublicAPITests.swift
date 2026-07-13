import Testing
import TestDoubles
import TestDoublesFixtures

@Suite struct PublicAPITests {
    @Test func intendedSynchronousSurfaceCompilesAndWorks() throws {
        let stub = try Stub<any UserRepository>()
        stub.when { $0.find(id: equal(42)) }.returns("The Answer")
        stub.when {
            $0.find(id: matching(description: "positive", where: { $0 > 0 }))
        }.then {
            (id: Int) in "User \(id)"
        }
        stub.when { $0.find(id: any()) }.returns("Guest")

        let repository: any UserRepository = stub()
        #expect(repository.find(id: 42) == "The Answer")
        #expect(repository.find(id: 7) == "User 7")
        #expect(repository.find(id: -1) == "Guest")

        let ids = ArgumentCaptor<Int>()
        stub.verify(.exactly(3)) { $0.find(id: ids.capture()) }
        stub.verify(.never) { $0.search(query: any()) }
        #expect(ids.values == [42, 7, -1])
    }

    @Test func intendedExplicitAndAsyncSurfaceCompilesAndWorks() async throws {
        let stub = try Stub<any AsyncDataLoader>(
            .method(String.self, returning: String.self, isThrowing: true, isAsync: true),
            .method([String].self, returning: Void.self, isAsync: true),
            .getter(Int.self)
        )
        await stub.when { try await $0.load(url: any()) }.then {
            (url: String) async throws -> String in
            await Task.yield()
            return "loaded:\(url)"
        }
        await stub.when { await $0.prefetch(urls: any()) }
        stub.when { $0.cacheSize }.returns(8)

        let loader: any AsyncDataLoader = stub()
        #expect(try await loader.load(url: "/users") == "loaded:/users")
        await loader.prefetch(urls: ["/users"])
        #expect(loader.cacheSize == 8)

        await stub.verify { try await $0.load(url: equal("/users")) }
        await stub.verify(.exactly(1)) { await $0.prefetch(urls: any()) }
    }
}

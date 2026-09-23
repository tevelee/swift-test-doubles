import Testing
import TestDoubles
@testable import ManualStubBuildPluginIntegrationFixtures

@Suite struct ManualStubBuildPluginIntegrationTests {
    @Test func buildPluginGeneratesACompilingManualStub() {
        let stub = BuildGeneratedGreetingServiceStub()
        stub.when { $0.greeting(for: "Ada") }.thenReturn("Hello, Ada")
        stub.when { $0.requestCount }.thenReturn(1)

        let service: any BuildGeneratedGreetingService = stub()

        #expect(service.greeting(for: "Ada") == "Hello, Ada")
        #expect(service.requestCount == 1)
        stub.verify { $0.greeting(for: "Ada") }
        stub.verify { $0.requestCount }
    }

    @Test func generatedEffectfulGettersReturnConfiguredValues() async throws {
        let stub = BuildGeneratedEffectfulGettersStub()
        await stub.when { await $0.asyncValue }.thenReturn(1)
        stub.when { try $0.throwingValue }.thenReturn(2)
        await stub.when { try await $0.asyncThrowingValue }.thenReturn(3)
        stub.when { try $0.typedThrowingValue }.thenReturn(4)
        await stub.when { try await $0.asyncTypedThrowingValue }.thenReturn(5)
        await stub.when { await $0[asynchronous: 10] }.thenReturn(6)
        stub.when { try $0[throwing: 10] }.thenReturn(7)
        await stub.when { try await $0[asyncThrowing: 10] }.thenReturn(8)
        stub.when { try $0[typedThrowing: 10] }.thenReturn(9)
        await stub.when { try await $0[asyncTypedThrowing: 10] }.thenReturn(10)

        let service: any BuildGeneratedEffectfulGetters = stub()
        #expect(await service.asyncValue == 1)
        #expect(try service.throwingValue == 2)
        #expect(try await service.asyncThrowingValue == 3)
        #expect(try service.typedThrowingValue == 4)
        #expect(try await service.asyncTypedThrowingValue == 5)
        #expect(await service[asynchronous: 10] == 6)
        #expect(try service[throwing: 10] == 7)
        #expect(try await service[asyncThrowing: 10] == 8)
        #expect(try service[typedThrowing: 10] == 9)
        #expect(try await service[asyncTypedThrowing: 10] == 10)
    }

    @Test func generatedThrowingGettersPropagateConfiguredErrors() async {
        let stub = BuildGeneratedEffectfulGettersStub()
        stub.when { try $0.throwingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0.asyncThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0.typedThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0.asyncTypedThrowingValue }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0[throwing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0[asyncThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        stub.when { try $0[typedThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)
        await stub.when { try await $0[asyncTypedThrowing: 10] }.thenThrow(BuildGeneratedGetterFailure.rejected)

        let service: any BuildGeneratedEffectfulGetters = stub()
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service.throwingValue }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service.asyncThrowingValue }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service.typedThrowingValue }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service.asyncTypedThrowingValue }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service[throwing: 10] }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service[asyncThrowing: 10] }
        #expect(throws: BuildGeneratedGetterFailure.rejected) { try service[typedThrowing: 10] }
        await #expect(throws: BuildGeneratedGetterFailure.rejected) { try await service[asyncTypedThrowing: 10] }
    }

    @Test func classBoundProtocolsGenerateClassConformersForWeakReferences() {
        let stub = BuildGeneratedDetailDelegateStub()
        stub.when { $0.didFinish(text: Match.any()) }.thenDoNothing()
        stub.when { $0.didCancel() }.thenDoNothing()

        let delegate: any BuildGeneratedDetailDelegate = stub()
        weak var weakDelegate: (any BuildGeneratedDetailDelegate)? = delegate
        weakDelegate?.didFinish(text: "done")
        weakDelegate?.didCancel()

        stub.verify { $0.didFinish(text: "done") }
        stub.verify { $0.didCancel() }
        withExtendedLifetime(delegate) {}
    }

    @MainActor @Test func globalActorProtocolsKeepTheirIsolation() async {
        let stub = BuildGeneratedRouterStub()
        stub.when { $0.push(Match.any()) }.thenDoNothing()
        await stub.when { await $0.present(title: Match.any()) }.thenReturn(true)
        stub.when { $0.depth }.thenReturn(2)

        let router: any BuildGeneratedRouter = stub()
        router.push("home")

        #expect(await router.present(title: "Hello"))
        #expect(router.depth == 2)
        stub.verify { $0.push("home") }
    }

    @Test func primaryAssociatedTypesGenerateGenericConformers() {
        let stub = BuildGeneratedCacheStub<String, Int>()
        stub.when { $0.value(for: "a") }.thenReturn(1)
        stub.when { $0.value(for: Match.any()) }.thenReturn(nil)
        stub.when { $0.store(Match.any(), for: Match.any()) }.thenDoNothing()

        let cache: any BuildGeneratedCache<String, Int> = stub()
        cache.store(2, for: "b")

        #expect(cache.value(for: "a") == 1)
        #expect(cache.value(for: "b") == nil)
        stub.verify { $0.store(2, for: "b") }
    }

    @Test func autoclosureArgumentsKeepEveryParameterAndPosition() {
        let stub = BuildGeneratedLoggerStub()
        stub.when {
            $0.log(Match.any(), Match.any(), file: Match.any(), line: Match.any())
        }.thenDoNothing()

        stub().log(.error, "charge failed: offline", file: "Checkout.swift", line: 89)

        stub.verify {
            $0.log(
                Match.equal(.error),
                Match.containsSubstring("offline"),
                file: Match.equal("Checkout.swift"),
                line: Match.equal(89)
            )
        }
    }

    @Test func nonescapingClosuresAreLentToHandlers() async throws {
        let stub = BuildGeneratedTransformerStub()
        stub.when { $0.map(Match.any(), transform: Match.any()) }
            .then { (values: [Int], transform: @escaping (Int) -> Int) in values.map(transform) }
        stub.when { $0.tryMap(Match.any(), transform: Match.any()) }
            .then { (values: [Int], transform: @escaping (Int) throws -> Int) in
                try values.map(transform)
            }
        stub.when { $0.load(Match.any(), completion: Match.any()) }
            .then { (path: String, completion: @escaping (Result<Int, any Error>) -> Void) in
                completion(.success(path.count))
            }
        stub.when { $0.visit(Match.any()) }
            .then { (body: @escaping (inout Int) -> Void) -> Int in
                var value = 1
                body(&value)
                return value
            }
        await stub.when { await $0.perform(Match.any()) }
            .then { (work: @escaping @Sendable () async -> Void) in await work() }

        let transformer: any BuildGeneratedTransformer = stub()
        #expect(transformer.map([1, 2]) { $0 * 10 } == [10, 20])
        #expect(try transformer.tryMap([1]) { $0 + 1 } == [2])
        #expect(throws: BuildGeneratedGetterFailure.rejected) {
            try transformer.tryMap([1]) { _ in throw BuildGeneratedGetterFailure.rejected }
        }
        var loaded: Int?
        transformer.load("four") { loaded = try? $0.get() }
        #expect(loaded == 4)
        #expect(transformer.visit { $0 += 41 } == 42)
        await transformer.perform {}
        stub.verify { $0.map([1, 2], transform: Match.any()) }
    }

    @Test func opaqueParametersShareOneRouteForEveryConcreteType() {
        let stub = BuildGeneratedAggregatorStub()
        stub.when { $0.sum(Match.any() as [Int]) }
            .then { (numbers: any Sequence<Int>) in numbers.reduce(0, +) }

        let aggregator: any BuildGeneratedAggregator = stub()

        #expect(aggregator.sum([1, 2, 3]) == 6)
        #expect(aggregator.sum(Set([4, 5])) == 9)
        #expect(aggregator.sum(1 ... 3) == 6)
    }
}

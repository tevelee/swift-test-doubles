import IssueReporting
import Testing
@testable import TestDoubles

private protocol ManualService {
    func fetch(id: Int) -> String
    func add(_ a: Int, _ b: Int) -> Int
    func reset()
    var count: Int { get set }
    func load() async -> String
    func tick() async
    func save(_ item: String) throws
    func refresh() async throws -> String
    var token: String { get throws }
    var asyncCount: Int { get async }
    var asyncToken: String { get async throws }
}

private struct ManualServiceStub: ManualService, StubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.fetch(id: id) }
    func add(_ a: Int, _ b: Int) -> Int { stub.add(a, b) }
    func reset() { stub.reset() }
    var count: Int {
        get { stub.count }
        set { stub.count = newValue }
    }
    func load() async -> String { await stub.load() }
    func tick() async { await stub.tick() }
    func save(_ item: String) throws { try stub.throwing.save(item) }
    func refresh() async throws -> String { try await stub.throwing.refresh() }
    var token: String { get throws { try stub.throwing.token } }
    var asyncCount: Int { get async { await stub.asyncCall() } }
    var asyncToken: String { get async throws { try await stub.asyncThrowingCall() } }
}

private struct SaveError: Error, Equatable {}

@Suite struct ManualStubTests {
    @Test func baseRouteSyncMethodsMatchAndReturn() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: any()) }.thenReturn("guest")
        stub.when { $0.fetch(id: equal(42)) }.thenReturn("Alice")
        stub.when { $0.add(any(), any()) }.then { (a: Int, b: Int) in a + b }

        let service: any ManualService = stub()
        #expect(service.fetch(id: 1) == "guest")
        #expect(service.fetch(id: 42) == "Alice")
        #expect(service.add(20, 22) == 42)

        stub.verify { $0.fetch(id: equal(42)) }
        stub.verify(.exactly(2)) { $0.fetch(id: any()) }
    }

    @Test func baseRouteVoidMethodRecordsAndVerifies() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.reset() }.thenDoNothing()

        let service: any ManualService = stub()
        service.reset()
        service.reset()

        stub.verify(.exactly(2)) { $0.reset() }
        stub.verify(.never()) { $0.fetch(id: any()) }
    }

    @Test func baseRouteGetterAndSetterMatchAndVerify() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.count }.thenReturn(7)
        stub.when { $0.count = any() }.thenDoNothing()

        var service: any ManualService = stub()
        #expect(service.count == 7)
        service.count = 9

        stub.verify { $0.count = equal(9) }
    }

    @Test func baseRouteAsyncMethodsMatchAndReturn() async {
        let stub = ManualStub<ManualServiceStub>()
        await stub.when { await $0.load() }.then { () async -> String in "loaded" }
        await stub.when { await $0.tick() }.thenDoNothing()

        let service: any ManualService = stub()
        #expect(await service.load() == "loaded")
        await service.tick()

        await stub.verify { await $0.load() }
        await stub.verify(.exactly(1)) { await $0.tick() }
    }

    @Test func throwingRouteSyncMethodPropagatesSuccessAndFailure() throws {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { try $0.save(equal("ok")) }.thenDoNothing()
        stub.when { try $0.save(equal("bad")) }.then { (_: String) throws -> Void in
            throw SaveError()
        }

        let service: any ManualService = stub()
        try service.save("ok")
        #expect(throws: SaveError.self) {
            try service.save("bad")
        }

        stub.verify(.exactly(2)) { try $0.save(any()) }
    }

    @Test func throwingRouteAsyncMethodAndGetterWork() async throws {
        let stub = ManualStub<ManualServiceStub>()
        await stub.when { try await $0.refresh() }.then { () async throws -> String in "fresh" }
        stub.when { try $0.token }.thenReturn("secret")

        let service: any ManualService = stub()
        #expect(try await service.refresh() == "fresh")
        #expect(try service.token == "secret")

        await stub.verify { try await $0.refresh() }
        stub.verify { try $0.token }
    }

    @Test func explicitFallbacksReachAsyncPropertyGetters() async throws {
        // asyncCount/asyncToken forward to `stub.asyncCall()`/`stub.asyncThrowingCall()`
        // internally (see ManualServiceStub above) — the only reachable route
        // for an async property getter. Registration goes through the
        // conformer's own property, exactly as playback does, so both calls
        // intern to the same key regardless of what #function evaluates to
        // inside a property accessor.
        let stub = ManualStub<ManualServiceStub>()
        await stub.when { await $0.asyncCount }.thenReturn(3)
        await stub.when { try await $0.asyncToken }.thenReturn("explicit")

        let service: any ManualService = stub()
        #expect(await service.asyncCount == 3)
        #expect(try await service.asyncToken == "explicit")
    }

    @Test func sequencedReturnsServeConsecutiveCallsThenRepeat() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: equal(1)) }.thenReturn("first", "second")

        let service: any ManualService = stub()
        #expect(service.fetch(id: 1) == "first")
        #expect(service.fetch(id: 1) == "second")
        #expect(service.fetch(id: 1) == "second")
    }

    @Test func behaviorChainMixesNoOpsAndErrorsThenRepeatsTheLast() throws {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { try $0.save(any()) }
            .thenDoNothing()
            .thenThrow(SaveError())
            .thenDoNothing()

        let service: any ManualService = stub()
        try service.save("first")
        #expect(throws: SaveError.self) { try service.save("second") }
        try service.save("third")
        try service.save("fourth")
    }

    @Test func argumentCaptorCollectsMatchingArguments() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: any()) }.thenReturn("x")

        let service: any ManualService = stub()
        _ = service.fetch(id: 1)
        _ = service.fetch(id: 2)

        let captor = ArgumentCaptor<Int>()
        stub.verify { $0.fetch(id: captor.capture()) }
        #expect(captor.values == [1, 2])
    }

    @Test func verifyInOrderMatchesRelativeCallSubsequence() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: any()) }.thenReturn("x")

        let service: any ManualService = stub()
        _ = service.fetch(id: 1)
        _ = service.fetch(id: 99)
        _ = service.fetch(id: 2)

        stub.verifyInOrder {
            _ = $0.fetch(id: equal(1))
            _ = $0.fetch(id: equal(2))
        }
    }

    @Test func verifyInOrderSupportsMixedMethodsGettersAndSetters() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: any()) }.thenReturn("x")
        stub.when { $0.count }.thenReturn(7)
        stub.when { $0.count = any() }.thenDoNothing()
        stub.when { $0.reset() }.thenDoNothing()
        var service: any ManualService = stub()

        _ = service.fetch(id: 1)
        service.count = 2
        _ = service.count
        service.reset()

        stub.verifyInOrder(mutating: {
            _ = $0.fetch(id: equal(1))
            $0.count = equal(2)
            _ = $0.count
            $0.reset()
        })

        stub.verify(.exactly(1)) { $0.count = equal(2) }
    }

    @Test func verifyInOrderReportsManualSetterOrderFailures() {
        let stub = ManualStub<ManualServiceStub>()
        stub.when { $0.fetch(id: any()) }.thenReturn("x")
        stub.when { $0.count = any() }.thenDoNothing()
        var service: any ManualService = stub()
        _ = service.fetch(id: 1)
        service.count = 2

        expectReportsIssue {
            stub.verifyInOrder(mutating: {
                $0.count = equal(2)
                _ = $0.fetch(id: equal(1))
            })
        } matching: {
            $0.description.contains("expectation 2")
        }
    }
}

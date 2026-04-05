import Testing
@testable import TestDoubles

// MARK: - Test protocol (simulates a protocol from a precompiled module — no real conformer needed)

private protocol FakeService {
    func find(id: Int) -> String
    func search(query: String, limit: Int) -> [String]
    var count: Int { get }
    func reset()
    func save(_ item: String) throws
    func load() async -> [String]
}

// MARK: - User-written stub struct

/// Demonstrates both approaches side by side.
///
/// Approach A (@dynamicMemberLookup) works for:
///   - Non-void methods with labeled args: `stub.find(id: id)`
///   - Property getters: `stub.count`
///
/// Approach B (#function default) is required for:
///   - Void zero-argument methods (subscript disambiguation ambiguity)
///   - Throwing methods
///   - Async methods
private struct FakeServiceStub: FakeService, StubConformer {
    let stub: Stub<Self>

    // Approach A
    func find(id: Int) -> String               { stub.find(id: id) }
    func search(query: String, limit: Int) -> [String] { stub.search(query: query, limit: limit) }
    var count: Int                               { stub.count }

    // Approach B (void zero-arg, throwing, async)
    func reset()                               { stub.call() }
    func save(_ item: String) throws           { try stub.throwingCall(item) }
    func load() async -> [String]              { await stub.asyncCall() }
}

// MARK: - Tests

@Suite struct ManualStubTests {

    // MARK: Basic method stubbing

    @Test func exactMatch() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: equal(42)) }.returns("Alice")
        let sut: any FakeService = stub()
        #expect(sut.find(id: 42) == "Alice")
    }

    @Test func wildcardMatcher() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any()) }.returns("anyone")
        let sut: any FakeService = stub()
        #expect(sut.find(id: 99) == "anyone")
        #expect(sut.find(id: 0) == "anyone")
    }

    @Test func predicateMatcher() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
        stub.when { $0.find(id: any(where: { $0 <= 100 })) }.returns("Regular")
        let sut: any FakeService = stub()
        #expect(sut.find(id: 101) == "VIP")
        #expect(sut.find(id: 50) == "Regular")
    }

    @Test func specificityResolution() {
        let stub = Stub<FakeServiceStub>()
        // Register wildcard first, then specific — specific should win
        stub.when { $0.find(id: any()) }.returns("default")
        stub.when { $0.find(id: equal(42)) }.returns("specific")
        let sut: any FakeService = stub()
        #expect(sut.find(id: 42) == "specific")
        #expect(sut.find(id: 7) == "default")
    }

    @Test func multiArgMethod() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.search(query: equal("swift"), limit: equal(10)) }.returns(["Swift", "SwiftUI"])
        stub.when { $0.search(query: any(), limit: any()) }.returns([])
        let sut: any FakeService = stub()
        #expect(sut.search(query: "swift", limit: 10) == ["Swift", "SwiftUI"])
        #expect(sut.search(query: "kotlin", limit: 5) == [])
    }

    // MARK: Property stubbing

    @Test func propertyGetter() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.count }.returns(42)
        let sut: any FakeService = stub()
        #expect(sut.count == 42)
    }

    @Test func propertyGetterMultipleTimes() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.count }.returns(7)
        let sut: any FakeService = stub()
        #expect(sut.count == 7)
        #expect(sut.count == 7)
    }

    // MARK: Void methods

    @Test func voidMethod() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.reset() }
        let sut: any FakeService = stub()
        sut.reset()
        stub.verify { $0.reset() }.wasCalled()
    }

    // MARK: Verify

    @Test func verifyCalledOnce() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any()) }.returns("x")
        let sut: any FakeService = stub()
        _ = sut.find(id: 1)
        stub.verify { $0.find(id: any()) }.wasCalled()
    }

    @Test func verifyCalledNTimes() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any()) }.returns("x")
        let sut: any FakeService = stub()
        _ = sut.find(id: 1)
        _ = sut.find(id: 2)
        stub.verify(called: 2) { $0.find(id: any()) }
    }

    @Test func verifyNeverCalled() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any()) }.returns("x")
        stub.verify(never: { $0.find(id: any()) })
    }

    @Test func verifyWithArgs() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.find(id: any()) }.returns("x")
        let sut: any FakeService = stub()
        _ = sut.find(id: 99)
        stub.verify { $0.find(id: any()) }.withArgs { calls in
            #expect(calls.count == 1)
            #expect(calls[0][0] as? Int == 99)
        }
    }

    // MARK: Throwing methods (Approach B)

    @Test func throwingMethodThrows() {
        let stub = Stub<FakeServiceStub>()
        struct SaveError: Error {}
        stub.when { try $0.save(any()) }.then { throw SaveError() }
        let sut: any FakeService = stub()
        #expect(throws: SaveError.self) { try sut.save("item") }
    }

    @Test func throwingMethodSucceeds() throws {
        let stub = Stub<FakeServiceStub>()
        stub.when { try $0.save(any()) }.returns(())
        let sut: any FakeService = stub()
        try sut.save("item")
        stub.verify { try $0.save(any()) }.wasCalled()
    }

    // MARK: Async methods (Approach B)

    @Test func asyncMethod() async {
        let stub = Stub<FakeServiceStub>()
        await stub.when { await $0.load() }.returns(["a", "b"])
        let sut: any FakeService = stub()
        let result = await sut.load()
        #expect(result == ["a", "b"])
    }

    // MARK: Argument captor

    @Test func argumentCaptor() {
        let stub = Stub<FakeServiceStub>()
        let captor = ArgumentCaptor<Int>()
        stub.when { $0.find(id: captor.capture()) }.returns("x")
        let sut: any FakeService = stub()
        _ = sut.find(id: 99)
        _ = sut.find(id: 42)
        #expect(captor.values == [99, 42])
    }

    // MARK: callAsFunction

    @Test func usableAsProtocol() {
        let stub = Stub<FakeServiceStub>()
        stub.when { $0.count }.returns(7)
        let sut: any FakeService = stub()
        #expect(sut.count == 7)
    }

    // MARK: Approach B fallback for sync methods

    @Test func approachBSyncFallback() {
        /// A stub that uses Approach B for all methods — e.g. when @dynamicMemberLookup
        /// disambiguation is not desired.
        struct BServiceStub: FakeService, StubConformer {
            let stub: Stub<Self>
            func find(id: Int) -> String          { stub.call(id) }
            func search(query: String, limit: Int) -> [String] { stub.call(query, limit) }
            var count: Int                          { stub.call() }
            func reset()                            { stub.call() }
            func save(_ item: String) throws       { try stub.throwingCall(item) }
            func load() async -> [String]          { await stub.asyncCall() }
        }

        let stub = Stub<BServiceStub>()
        stub.when { $0.find(id: equal(7)) }.returns("seven")
        let sut: any FakeService = stub()
        #expect(sut.find(id: 7) == "seven")
    }
}

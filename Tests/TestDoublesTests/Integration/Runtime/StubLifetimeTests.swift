import Testing
@testable import TestDoubles

protocol AutomaticLifetimeProbe {
    func value() -> Int
}

struct LinkedAutomaticLifetimeProbe: AutomaticLifetimeProbe {
    func value() -> Int { 0 }
}

private struct GenericLifetimeProbe<Value: AutomaticLifetimeProbe> {
    let value: Value
}

@inline(never)
private func readGenericLifetimeProbe(
    _ value: any AutomaticLifetimeProbe
) -> Int {
    func read<Value: AutomaticLifetimeProbe>(_ value: Value) -> Int {
        GenericLifetimeProbe(value: value).value.value()
    }
    return read(value)
}

protocol InheritedLifetimeBaseProbe {
    func baseValue() -> Int
}

protocol InheritedLifetimeChildProbe: InheritedLifetimeBaseProbe {
    func childValue() -> Int
}

struct LinkedInheritedLifetimeProbe: InheritedLifetimeChildProbe {
    func baseValue() -> Int { 0 }
    func childValue() -> Int { 0 }
}

protocol CompositionLifetimeA {
    func firstValue() -> Int
}

protocol CompositionLifetimeB {
    func secondValue() -> Int
}

struct LinkedCompositionLifetimeA: CompositionLifetimeA {
    func firstValue() -> Int { 0 }
}

struct LinkedCompositionLifetimeB: CompositionLifetimeB {
    func secondValue() -> Int { 0 }
}

protocol ExplicitLifetimeProbe {
    func value() -> Int
}

protocol AsyncLifetimeProbe {
    func value() async -> Int
}

private actor LifetimeSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard started == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite struct StubLifetimeTests {
    @Test func automaticExistentialOutlivesStub() throws {
        _ = LinkedAutomaticLifetimeProbe()
        var stub: Stub<any AutomaticLifetimeProbe>? = try Stub()
        stub?.when { $0.value() }.thenReturn(42)
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil

        #expect(weakStub.value == nil)
        #expect(probe.value() == 42)
    }

    @Test func repeatedMaterializationSharesBehaviorAndOutlivesStub() throws {
        _ = LinkedAutomaticLifetimeProbe()
        var stub: Stub<any AutomaticLifetimeProbe>? = try Stub()
        stub?.when { $0.value() }.thenReturn(42)
        let first = try #require(stub?())
        let second = try #require(stub?())

        stub = nil

        #expect(first.value() == 42)
        #expect(second.value() == 42)
    }

    @Test func genericMetadataCacheOutlivesFabricatedWitnessResources() throws {
        _ = LinkedAutomaticLifetimeProbe()

        for expected in 0 ..< 256 {
            let weakRecorder: WeakReference<StubRecorder>
            do {
                let stub = try Stub<any AutomaticLifetimeProbe>()
                stub.when { $0.value() }.thenReturn(expected)
                let probe = stub()
                weakRecorder = WeakReference(stub.recorder)

                #expect(readGenericLifetimeProbe(probe) == expected)
            }

            #expect(weakRecorder.value == nil)
        }
    }

    @Test func explicitExistentialOutlivesStub() throws {
        var stub: Stub<any ExplicitLifetimeProbe>? = try Stub(
            .method(returning: Int.self)
        )
        stub?.when { $0.value() }.thenReturn(42)
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil

        #expect(weakStub.value == nil)
        #expect(probe.value() == 42)
    }

    @Test func inheritedWitnessTableGraphOutlivesStub() throws {
        _ = LinkedInheritedLifetimeProbe()
        var stub: Stub<any InheritedLifetimeChildProbe>? = try Stub()
        stub?.when { $0.baseValue() }.thenReturn(21)
        stub?.when { $0.childValue() }.thenReturn(42)
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil

        #expect(weakStub.value == nil)
        #expect(probe.baseValue() == 21)
        #expect(probe.childValue() == 42)
    }

    @Test func compositionExistentialOutlivesStub() throws {
        _ = LinkedCompositionLifetimeA()
        _ = LinkedCompositionLifetimeB()
        var stub: Stub<any CompositionLifetimeA & CompositionLifetimeB>? = try Stub()
        stub?.when { $0.firstValue() }.thenReturn(21)
        stub?.when { $0.secondValue() }.thenReturn(42)
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil

        #expect(weakStub.value == nil)
        #expect(probe.firstValue() == 21)
        #expect(probe.secondValue() == 42)
    }

    @Test func suspendedAsyncCallOutlivesStub() async throws {
        var stub: Stub<any AsyncLifetimeProbe>? = try Stub(
            .method(returning: Int.self, isAsync: true)
        )
        let gate = LifetimeSuspensionGate()
        await stub?.when { await $0.value() }.then {
            () async throws -> Int in
            await gate.suspend()
            return 42
        }
        let probe = try #require(stub?())
        let weakStub = WeakReference(stub)

        stub = nil
        #expect(weakStub.value == nil)

        let task = Task { await probe.value() }
        await gate.waitUntilStarted()
        await gate.release()

        #expect(await task.value == 42)
    }
}

import TestDoubles
import Testing

private protocol FacadeValueSource {
    func value() -> Int
}

private struct LiveFacadeValueSource: FacadeValueSource {
    let storedValue: Int

    func value() -> Int { storedValue }
}

private struct FacadeValueSourceStubConformer: FacadeValueSource, ManualStubConformer {
    let stub: CompiledStub<Self>

    func value() -> Int { stub.call() }
}

private typealias FacadeValueSourceStub = CompiledStub<FacadeValueSourceStubConformer>

private protocol FacadeActorSource: Actor {
    func value() -> Int
}

private actor FacadeActorSourceStubConformer: FacadeActorSource, AutomaticStubConformer {
    typealias StubbedProtocol = any FacadeActorSource

    let stub: CompiledStub<FacadeActorSourceStubConformer>

    init(stub: CompiledStub<FacadeActorSourceStubConformer>) {
        self.stub = stub
    }

    static func eraseToStubbedProtocol(
        _ conformer: FacadeActorSourceStubConformer
    ) -> StubbedProtocol {
        conformer
    }

    func value() -> Int { stub.call() }
}

private typealias FacadeActorSourceStub = CompiledStub<FacadeActorSourceStubConformer>

@Suite("TestDouble construction facade")
struct TestDoubleConstructionFacadeTests {
    @Test func constructsARuntimeStubController() throws {
        _ = LiveFacadeValueSource(storedValue: 0)
        let stub = try TestDouble.stub(of: (any FacadeValueSource).self)
        stub.when { $0.value() }.thenReturn(42)

        #expect(stub().value() == 42)
        #expect(stub.constructionStrategy == .runtimeGenerated)
    }

    @Test func generatedControllerUsesAutomaticCompiledFallback() async {
        let stub = TestDouble.stub(using: FacadeActorSourceStub.self)
        await stub.when { await $0.value() }.thenReturn(43)

        let source: any FacadeActorSource = stub()
        #expect(await source.value() == 43)
        #expect(stub.constructionStrategy == .compiledFallback)
    }

    @Test func constructsAForcedCompiledController() {
        let stub = TestDouble.compiled(FacadeValueSourceStub.self)
        stub.when { $0.value() }.thenReturn(44)

        #expect(stub().value() == 44)
    }

    @Test func constructsAForwardingSpyControllerForAnExplicitProtocol() throws {
        let spy = try TestDouble.spy(
            of: (any FacadeValueSource).self,
            forwardingTo: LiveFacadeValueSource(storedValue: 45)
        )

        #expect(spy().value() == 45)

        spy.when { $0.value() }.thenReturn(46)
        #expect(spy().value() == 46)
    }

    @Test func constructsADummyController() throws {
        let dummy = try TestDouble.dummy(of: (any FacadeValueSource).self)
        let source: any FacadeValueSource = dummy()

        withExtendedLifetime(source) {}
    }
}

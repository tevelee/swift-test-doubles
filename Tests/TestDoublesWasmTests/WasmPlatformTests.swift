import Testing
import TestDoubles

// A small, hand-written stub covering the same protocol shape ManualStub
// targets on every platform the runtime trampoline can't run on. Kept in its
// own target with no Dispatch, Foundation-heavy fixtures, or dynamic test
// support library, so it stays buildable everywhere including
// wasm32-unknown-wasip1.
protocol WasmDemoService {
    func fetch(id: Int) -> String
    func reset()
    var count: Int { get }
}

struct WasmDemoServiceStub: WasmDemoService, StubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.fetch(id: id) }
    func reset() { stub.reset() }
    var count: Int { stub.count }
}

@Suite struct WasmPlatformTests {
    @Test func manualStubConfiguresRecordsAndVerifiesOnEveryPlatform() {
        let stub = ManualStub<WasmDemoServiceStub>()
        stub.when { $0.fetch(id: equal(42)) }.thenReturn("Alice")
        stub.when { $0.fetch(id: any()) }.thenReturn("stranger")
        stub.when { $0.count }.thenReturn(3)
        stub.when { $0.reset() }.thenDoNothing()

        let sut: any WasmDemoService = stub()

        #expect(sut.fetch(id: 42) == "Alice")
        #expect(sut.fetch(id: 7) == "stranger")
        #expect(sut.count == 3)
        sut.reset()

        stub.verify(.exactly(2)) { $0.fetch(id: any()) }
        stub.verify { $0.reset() }
        stub.verify { $0.count }
        stub.verifyNoMoreInteractions()
    }

    #if os(WASI)
        @Test func runtimeGeneratedStubConstructionFailsClosedOnWasi() throws {
            #expect(throws: StubError.self) {
                _ = try Stub<any WasmDemoService>()
            }
        }
    #endif
}

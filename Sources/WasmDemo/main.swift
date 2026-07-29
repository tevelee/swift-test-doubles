import TestDoubles

// Demonstrates the WebAssembly story end-to-end as a standalone executable,
// run under a WASI runtime (see Scripts/validate-wasm.sh): ManualStub works
// fully, since it needs no runtime code generation, while the runtime-
// fabricated Stub/Spy path fails closed with an actionable diagnostic instead
// of silently misbehaving, exactly as it does on physical Apple devices.

protocol WasmDemoService {
    func fetch(id: Int) -> String
    func reset()
    var count: Int { get }
}

struct WasmDemoServiceStub: WasmDemoService, ManualStubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.requirements.fetch(id: id) }
    func reset() { stub.requirements.reset() }
    var count: Int { stub.requirements.count }
}

func demonstrateManualStub() {
    let stub = ManualStub<WasmDemoServiceStub>()
    stub.when { $0.fetch(id: Match.equal(42)) }.thenReturn("Alice")
    stub.when { $0.fetch(id: Match.any()) }.thenReturn("stranger")
    stub.when { $0.count }.thenReturn(3)
    stub.when { $0.reset() }.thenDoNothing()

    let sut: any WasmDemoService = stub()

    precondition(sut.fetch(id: 42) == "Alice")
    precondition(sut.fetch(id: 7) == "stranger")
    precondition(sut.count == 3)
    sut.reset()

    print("ManualStub: configured, invoked, and fully usable on wasm32-wasi.")
}

func demonstrateRuntimeStubFailsClosed() {
    do {
        _ = try Stub<any WasmDemoService>()
        fatalError("Expected Stub construction to fail closed on wasm32-wasi.")
    } catch {
        print("Stub<P>(): failed closed with \(error), as documented for this platform.")
    }
}

demonstrateManualStub()
demonstrateRuntimeStubFailsClosed()
print("WasmDemo: all checks passed.")

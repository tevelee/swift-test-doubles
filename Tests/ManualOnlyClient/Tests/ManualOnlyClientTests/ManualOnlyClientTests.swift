import TestDoubles
import Testing

private protocol ManualOnlyService {
    func value(for id: Int) -> String
}

private struct ManualOnlyServiceStub: ManualOnlyService, StubConformer {
    let stub: ManualStub<Self>

    func value(for id: Int) -> String {
        stub.value(for: id)
    }
}

@Test
func manualStubWorksWithoutRuntimeFabrication() {
    let stub = ManualStub<ManualOnlyServiceStub>()
    stub.when { $0.value(for: Match.equal(42)) }.thenReturn("forty-two")

    let service: any ManualOnlyService = stub()

    #expect(service.value(for: 42) == "forty-two")
    stub.verify(1...) { $0.value(for: 42) }
}

@Test
func runtimeStubConstructionExplainsDisabledTrait() {
    #expect(throws: StubError.self) {
        _ = try Stub<any ManualOnlyService>()
    }

    do {
        _ = try Stub<any ManualOnlyService>()
    } catch {
        #expect(String(describing: error).contains("RuntimeStubs"))
    }
}

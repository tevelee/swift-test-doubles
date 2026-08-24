import TestDoubles
import Testing

private protocol ManualOnlyService {
    func value(for id: Int) -> String
}

private struct ManualOnlyServiceStub: ManualOnlyService, ManualStubConformer {
    let stub: ManualStub<Self>

    func value(for id: Int) -> String {
        stub.value(for: id)
    }
}

private struct ManualClosureClient: Sendable {
    var load: @Sendable (Int) async -> String
}

private let manualClosureClientTestValues =
    ClientDoublePreset<ManualClosureClient> { endpoints in
        ManualClosureClient(
            load: endpoints.asyncFunction("load")
        )
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

@Test
func automaticStubUsesCompiledFallbackWithoutRuntimeTrait() {
    let stub = Stub<any ManualOnlyService>(
        fallingBackTo: ManualOnlyServiceStub.self,
        erasingWith: { $0 }
    )
    stub.when { $0.value(for: Match.equal(7)) }.thenReturn("seven")

    #expect(stub().value(for: 7) == "seven")
    #expect(stub.constructionStrategy == .compiledFallback)
    #expect(stub.runtimeFallbackReason?.description.contains("RuntimeStubs") == true)
}

@Test
func closureClientTestValueNeedsNeitherRuntimeFabricationNorMacros() async {
    let client = await manualClosureClientTestValues.testValue { stub in
        await stub.when { await $0.load(Match.equal(42)) }
            .thenReturn("forty-two")
    }

    #expect(await client.load(42) == "forty-two")
}

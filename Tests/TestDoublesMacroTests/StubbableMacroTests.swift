#if TESTDOUBLES_STUBBABLE_MACROS
    import TestDoublesMacros
    import Testing

    @Stubbable
    protocol StubbableMacroService {
        func fetch(_ identifier: Int) -> String
        var displayName: String { get set }
    }

    @Suite struct StubbableMacroTests {
        @Test func generatesAConfigurableManualStub() {
            let stub = ManualStub<StubbableMacroServiceManualStub>()
            stub.when { $0.fetch(42) }.thenReturn("answer")
            stub.when { $0.displayName }.thenReturn("Test Double")

            let service: any StubbableMacroService = stub()

            #expect(service.fetch(42) == "answer")
            #expect(service.displayName == "Test Double")
            stub.verify { $0.fetch(42) }
            stub.verify { $0.displayName }
        }
    }
#endif

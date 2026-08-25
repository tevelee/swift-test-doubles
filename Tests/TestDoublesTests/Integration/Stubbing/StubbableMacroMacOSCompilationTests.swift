#if os(macOS) && TESTDOUBLES_STUBBABLE_MACROS
    import Foundation
    import TestDoubles
    import TestDoublesMacros
    import Testing

    @Stubbable
    private protocol MacroLoadable {
        func load() async throws -> Data
    }

    struct StubbableMacroMacOSCompilationTests {
        @Test func expansionCompilesAndForwardsAsyncThrowingResults() async throws {
            let stub = MacroLoadableStub()
            let expected = Data([2, 3, 5, 7])
            await stub.when { try await $0.load() }.thenReturn(expected)

            let loadable: any MacroLoadable = stub()

            #expect(try await loadable.load() == expected)
        }
    }
#endif

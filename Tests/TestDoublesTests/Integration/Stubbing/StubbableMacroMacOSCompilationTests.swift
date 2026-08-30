#if os(macOS) && TESTDOUBLES_STUBBABLE_MACROS
    import TestDoubles
    import TestDoublesResilientFixtures
    import TestDoublesMacros
    import Testing

    @Stubbable
    private protocol MacroLoadable {
        func load(_ identifier: Int) async throws -> ResilientValueArgument
    }

    struct StubbableMacroMacOSCompilationTests {
        @Test func generatedAliasAutomaticallyFallsBackForCustomResilientResults() async throws {
            let stub = MacroLoadableStub.automatic()
            let expected = ResilientValueArgument(first: 2, second: 3)
            await stub.when(returning: expected) {
                try await $0.load(Match.equal(5))
            }.thenReturn(expected)

            let loadable: any MacroLoadable = stub()

            #expect(try await loadable.load(5) == expected)
            #expect(stub.constructionStrategy == .compiledFallback)
            #expect(stub.runtimeFallbackReason != nil)
        }
    }
#endif

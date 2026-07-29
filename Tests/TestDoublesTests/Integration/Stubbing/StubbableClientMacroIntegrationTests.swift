#if TESTDOUBLES_STUBBABLE_MACROS
    import TestDoubles
    import TestDoublesMacros
    import Testing

    private enum GeneratedClientFailure: Error, Equatable {
        case rejected
    }

    @StubbableClient
    private struct GeneratedClosureClient: Sendable {
        var format: @Sendable (Int, String) -> String
        var load: @Sendable (Int, String) async throws -> [String]
        var save: @Sendable (Int) throws(GeneratedClientFailure) -> String
    }

    @Suite struct StubbableClientMacroIntegrationTests {
        @Test func generatedPresetStubsAndForwardsClosureFields() async throws {
            let failing = GeneratedClosureClientDoubles.preset.failing()
            failing.when {
                $0.format(Match.equal(2), Match.equal("items"))
            }.thenReturn("two items")
            #expect(failing().format(2, "items") == "two items")

            let live = GeneratedClosureClient(
                format: { "\($0) \($1)" },
                load: { ["\($0)-\($1)"] },
                save: { "saved-\($0)" }
            )
            let spy = GeneratedClosureClientDoubles.preset.spy(
                forwardingTo: live
            )
            spy.when {
                $0.format(Match.equal(3), Match.any())
            }.thenReturn("overridden")

            let client = spy()
            #expect(client.format(3, "items") == "overridden")
            #expect(client.format(4, "items") == "4 items")
            #expect(try await client.load(5, "news") == ["5-news"])
            #expect(try client.save(6) == "saved-6")
            #expect(spy.history.stubbed.callCount == 1)
            #expect(spy.history.forwarded.callCount == 3)
        }
    }
#endif

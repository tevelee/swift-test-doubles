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

    @StubbableClient
    private struct GeneratedGenericClient<Value: Sendable>: Sendable
    where Value: Equatable {
        enum Failure: Error {
            case rejected
        }

        typealias Load =
            @Sendable (String) async throws(Failure) -> Value

        var namespace: String
        var load: Load
        let identity: @Sendable (Value) -> Value = { $0 }
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

        @Test func generatedPresetSupportsGenericClientsAliasesAndInputs() async throws {
            let preset = GeneratedGenericClientDoubles<Int>.preset(
                namespace: "test"
            )
            let stub = await preset.failing { stub in
                await stub.when {
                    try await $0.load(Match.equal("value"))
                }.thenReturn(42)
            }

            let stubbed = stub()
            #expect(stubbed.namespace == "test")
            #expect(try await stubbed.load("value") == 42)
            #expect(stubbed.identity(7) == 7)

            let live = GeneratedGenericClient<Int>(
                namespace: "live",
                load: { $0.count }
            )
            let spy = preset.spy(forwardingTo: live)
            let forwarded = spy()
            #expect(forwarded.namespace == "test")
            #expect(try await forwarded.load("hello") == 5)
            #expect(spy.history.forwarded.callCount == 1)
        }
    }
#endif

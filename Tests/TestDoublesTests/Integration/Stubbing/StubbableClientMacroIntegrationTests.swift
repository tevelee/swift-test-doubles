#if TESTDOUBLES_STUBBABLE_MACROS
    import TestDoubles
    import TestDoublesFixtures
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

    @StubbableClient(
        aliasedEndpoints: "ping",
        "parse",
        "lookup",
        "transform",
        "save",
        "asyncSave",
        "legacy"
    )
    private struct GeneratedAliasedClient<Value: Sendable>: @unchecked Sendable {
        var scope: String
        var ping: FixtureClientPing
        var parse: FixtureClientParse
        var lookup: FixtureClientLookup
        var transform: FixtureClientTransform<Value>
        var save: FixtureClientSave
        var asyncSave: FixtureClientAsyncSave
        var legacy: FixtureClientLegacy

        init(seed: Value) {
            scope = "live"
            ping = { true }
            parse = { value, offset, enabled, scale in
                enabled ? value.count + offset + Int(scale) : 0
            }
            lookup = { "\($0)-\($1)-\($2)" }
            transform = { value, _ in value }
            save = { "saved-\($0)" }
            asyncSave = { "\($0)-\($1)" }
            legacy = { $0.count }
            _ = seed
        }
    }

    @Suite struct StubbableClientMacroIntegrationTests {
        @Test func generatedPresetExposesDependencyTestValues() {
            let direct: GeneratedClosureClient =
                GeneratedClosureClientDoubles.testValue
            let configured: GeneratedGenericClient<Int> =
                GeneratedGenericClientDoubles<Int>.testValue(
                    namespace: "dependencies"
                )

            #expect(configured.namespace == "dependencies")
            _ = direct
        }

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

        @Test func generatedPresetSupportsCustomInitializersAndExternalAliases() async throws {
            let preset = GeneratedAliasedClientDoubles<Int>.preset(
                scope: "test"
            )
            let stub = preset.failing()
            stub.when {
                $0.ping()
            }.thenReturn(false)
            stub.when {
                try $0.parse(
                    Match.equal("one"),
                    Match.equal(2),
                    Match.equal(true),
                    Match.equal(3)
                )
            }.thenReturn(6)
            await stub.when {
                await $0.lookup(
                    Match.equal(1),
                    Match.equal("value"),
                    Match.equal(true)
                )
            }.thenReturn("stubbed")
            stub.when {
                $0.transform(Match.equal(3), Match.equal(4))
            }.thenReturn(7)
            stub.when {
                try $0.save(Match.equal(5))
            }.thenReturn("stored")
            await stub.when {
                try await $0.asyncSave(
                    Match.equal(6),
                    Match.equal("value")
                )
            }.thenReturn("async-stored")
            await stub.when {
                try await $0.legacy(Match.equal("six"))
            }.thenReturn(6)

            let client = stub()
            #expect(client.scope == "test")
            #expect(client.ping() == false)
            #expect(try client.parse("one", 2, true, 3) == 6)
            #expect(await client.lookup(1, "value", true) == "stubbed")
            #expect(client.transform(3, 4) == 7)
            #expect(try client.save(5) == "stored")
            #expect(try await client.asyncSave(6, "value") == "async-stored")
            #expect(try await client.legacy("six") == 6)

            let live = GeneratedAliasedClient(seed: 42)
            let spy = preset.spy(forwardingTo: live)
            let forwarded = spy()
            #expect(forwarded.scope == "test")
            #expect(forwarded.ping())
            #expect(try forwarded.parse("one", 2, true, 3) == 8)
            #expect(await forwarded.lookup(2, "live", false) == "2-live-false")
            #expect(forwarded.transform(8, 9) == 8)
            #expect(try forwarded.save(10) == "saved-10")
            #expect(try await forwarded.asyncSave(11, "live") == "11-live")
            #expect(try await forwarded.legacy("eleven") == 6)
            #expect(spy.history.forwarded.callCount == 7)
        }
    }
#endif

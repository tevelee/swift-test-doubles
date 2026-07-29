import TestDoubles
import Testing

private enum ClientStubFailure: Error, Equatable {
    case rejected(Int)
}

private struct ClosureFieldClient: Sendable {
    var version: @Sendable () -> String
    var format: @Sendable (Int, String) -> String
    var combine:
        @Sendable (
            Int,
            Int,
            Int,
            Int,
            Int,
            Int,
            Int,
            Int
        ) -> Int
    var save: @Sendable (Int) throws -> String
    var typedSave: @Sendable (Int) throws(ClientStubFailure) -> String
    var notify: @Sendable (String) -> Void
    var lookup: @Sendable (Int) async -> String
    var load: @Sendable (Int, String) async throws -> [String]
    var typedLoad: @Sendable (Int) async throws(ClientStubFailure) -> String
}

private func makeClosureFieldClientStub() -> ClientStub<ClosureFieldClient> {
    ClientStub<ClosureFieldClient> { endpoints in
        ClosureFieldClient(
            version: endpoints.function("version"),
            format: endpoints.function("format"),
            combine: endpoints.function("combine"),
            save: endpoints.throwingFunction("save"),
            typedSave: endpoints.throwingFunction(
                "typedSave",
                throwing: ClientStubFailure.self
            ),
            notify: endpoints.function("notify"),
            lookup: endpoints.asyncFunction("lookup"),
            load: endpoints.asyncThrowingFunction("load"),
            typedLoad: endpoints.asyncThrowingFunction(
                "typedLoad",
                throwing: ClientStubFailure.self
            )
        )
    }
}

private func makeClosureFieldClientPreset() -> ClientDoublePreset<ClosureFieldClient> {
    ClientDoublePreset<ClosureFieldClient> { endpoints in
        ClosureFieldClient(
            version: endpoints.function(
                "version",
                forwarding: { live in live.version() }
            ),
            format: endpoints.function(
                "format",
                forwarding: { live, value, unit in
                    live.format(value, unit)
                }
            ),
            combine: endpoints.function(
                "combine",
                forwarding: { live, a, b, c, d, e, f, g, h in
                    live.combine(a, b, c, d, e, f, g, h)
                }
            ),
            save: endpoints.throwingFunction(
                "save",
                forwarding: { live, value in
                    try live.save(value)
                }
            ),
            typedSave: endpoints.throwingFunction(
                "typedSave",
                throwing: ClientStubFailure.self,
                forwarding: {
                    (
                        live: ClosureFieldClient,
                        value: Int
                    ) throws(ClientStubFailure) -> String in
                    try live.typedSave(value)
                }
            ),
            notify: endpoints.function(
                "notify",
                forwarding: { live, message in
                    live.notify(message)
                }
            ),
            lookup: endpoints.asyncFunction(
                "lookup",
                forwarding: { live, value in
                    await live.lookup(value)
                }
            ),
            load: endpoints.asyncThrowingFunction(
                "load",
                forwarding: { live, value, category in
                    try await live.load(value, category)
                }
            ),
            typedLoad: endpoints.asyncThrowingFunction(
                "typedLoad",
                throwing: ClientStubFailure.self,
                forwarding: {
                    (
                        live: ClosureFieldClient,
                        value: Int
                    ) async throws(ClientStubFailure) -> String in
                    try await live.typedLoad(value)
                }
            )
        )
    }
}

private func makeLiveClosureFieldClient() -> ClosureFieldClient {
    ClosureFieldClient(
        version: { "live" },
        format: { "\($0) \($1)" },
        combine: { $0 + $1 + $2 + $3 + $4 + $5 + $6 + $7 },
        save: {
            guard $0 >= 0 else {
                throw ClientStubFailure.rejected($0)
            }
            return "saved-\($0)"
        },
        typedSave: { (value: Int) throws(ClientStubFailure) -> String in
            guard value >= 0 else {
                throw ClientStubFailure.rejected(value)
            }
            return "typed-saved-\(value)"
        },
        notify: { _ in },
        lookup: { "lookup-\($0)" },
        load: { ["\($0)-\($1)"] },
        typedLoad: { (value: Int) async throws(ClientStubFailure) -> String in
            guard value >= 0 else {
                throw ClientStubFailure.rejected(value)
            }
            return "typed-loaded-\(value)"
        }
    )
}

@Suite struct ClientStubTests {
    @Test func concreteClientUsesTheProtocolStubConfigurationVocabulary() async throws {
        let stub = makeClosureFieldClientStub().named("api client")
        stub.when { $0.version() }.thenReturn("1.0")
        stub.when {
            $0.format(Match.equal(7), Match.equal("items"))
        }.thenReturn("7 items")
        stub.when {
            $0.combine(
                Match.equal(1),
                Match.equal(2),
                Match.equal(3),
                Match.equal(4),
                Match.equal(5),
                Match.equal(6),
                Match.equal(7),
                Match.equal(8)
            )
        }.thenReturn(36)
        stub.when { try $0.save(Match.equal(7)) }.thenReturn("saved")
        stub.when { $0.notify(Match.equal("ready")) }.thenDoNothing()
        await stub.when {
            await $0.lookup(Match.equal(8))
        }.thenReturn("eight")
        await stub.when(returning: [String]()) {
            try await $0.load(
                Match.equal(9),
                Match.equal("featured")
            )
        }.thenReturn(["nine"])

        let client: ClosureFieldClient = stub()
        #expect(client.version() == "1.0")
        #expect(client.format(7, "items") == "7 items")
        #expect(client.combine(1, 2, 3, 4, 5, 6, 7, 8) == 36)
        #expect(try client.save(7) == "saved")
        client.notify("ready")
        #expect(await client.lookup(8) == "eight")
        #expect(try await client.load(9, "featured") == ["nine"])

        stub.verify { $0.version() }
        stub.verify {
            $0.format(Match.equal(7), Match.equal("items"))
        }
        stub.verify {
            $0.combine(
                Match.equal(1),
                Match.equal(2),
                Match.equal(3),
                Match.equal(4),
                Match.equal(5),
                Match.equal(6),
                Match.equal(7),
                Match.equal(8)
            )
        }
        stub.verify { try $0.save(Match.equal(7)) }
        stub.verify { $0.notify(Match.equal("ready")) }
        await stub.verify {
            await $0.lookup(Match.equal(8))
        }
        await stub.verify(returning: [String]()) {
            try await $0.load(
                Match.equal(9),
                Match.equal("featured")
            )
        }
        stub.verifyNoMoreInteractions()
    }

    @Test func typedThrowingEndpointPreservesItsFailureChannel() async throws {
        let stub = makeClosureFieldClientStub()
        stub.when {
            try $0.typedSave(Match.equal(1))
        }.thenReturn("saved")
        stub.when {
            try $0.typedSave(Match.equal(2))
        }.thenThrow(ClientStubFailure.rejected(2))
        await stub.when {
            try await $0.typedLoad(Match.equal(1))
        }.thenReturn("first")
        await stub.when {
            try await $0.typedLoad(Match.equal(2))
        }.thenThrow(ClientStubFailure.rejected(2))

        let client = stub()
        #expect(try client.typedSave(1) == "saved")
        #expect(throws: ClientStubFailure.rejected(2)) {
            _ = try client.typedSave(2)
        }
        #expect(try await client.typedLoad(1) == "first")
        let failure = await #expect(throws: ClientStubFailure.self) {
            _ = try await client.typedLoad(2)
        }
        #expect(failure == .rejected(2))
    }

    @Test func everyMaterializedValueSharesConfigurationAndHistory() {
        let stub = makeClosureFieldClientStub()
        stub.when {
            $0.format(Match.any(), Match.any())
        }.then { (value: Int, unit: String) in
            "\(value) \(unit)"
        }

        let first = stub()
        let second = stub()
        #expect(first.format(1, "book") == "1 book")
        #expect(second.format(2, "books") == "2 books")

        stub.verify(.exactly(2)) {
            $0.format(Match.any(), Match.any())
        }
    }

    @Test func endpointsUseOneRecorderForOrderingAndReset() {
        let stub = makeClosureFieldClientStub()
        stub.when { $0.version() }.thenReturn("1.0")
        stub.when { $0.notify(Match.any()) }.thenDoNothing()

        let client = stub()
        _ = client.version()
        client.notify("ready")

        stub.verifyExactlyInOrder {
            _ = $0.version()
            $0.notify("ready")
        }

        stub.reset()
        stub.verify(.never) { $0.version() }
        stub.verify(.never) { $0.notify(Match.any()) }
    }

    @Test func clientSpyForwardsEveryEffectAndArbitraryArity() async throws {
        let spy = makeClosureFieldClientPreset().spy(
            forwardingTo: makeLiveClosureFieldClient()
        )
        let versions = spy.when { $0.version() }
        let combinations = spy.when {
            $0.combine(
                Match.any(),
                Match.any(),
                Match.any(),
                Match.any(),
                Match.any(),
                Match.any(),
                Match.any(),
                Match.any()
            )
        }
        let typedLoads = await spy.when {
            try await $0.typedLoad(Match.any())
        }

        let client = spy()
        #expect(client.version() == "live")
        #expect(client.combine(1, 2, 3, 4, 5, 6, 7, 8) == 36)
        #expect(try client.save(4) == "saved-4")
        #expect(throws: ClientStubFailure.rejected(-1)) {
            _ = try client.typedSave(-1)
        }
        #expect(await client.lookup(5) == "lookup-5")
        #expect(try await client.load(6, "news") == ["6-news"])
        #expect(try await client.typedLoad(7) == "typed-loaded-7")

        versions.forwarded.verify()
        combinations.forwarded.verify()
        typedLoads.forwarded.verify()
        #expect(spy.history.forwarded.callCount == 7)
        #expect(spy.history.stubbed.callCount == 0)
    }

    @Test func clientPresetBuildsLiveFailingAndPartialOverrideVariants() {
        let preset = makeClosureFieldClientPreset()
        let live = makeLiveClosureFieldClient()
        #expect(preset.live(live).version() == "live")

        let failing = preset.failing()
        failing.when { $0.version() }.thenReturn("test")
        #expect(failing().version() == "test")

        let partial = preset.overriding(live) { spy in
            spy.when {
                $0.format(Match.equal(7), Match.any())
            }.thenForward()
            spy.when {
                $0.format(Match.any(), Match.any())
            }.thenReturn("overridden")
        }
        let formats = partial.when {
            $0.format(Match.any(), Match.any())
        }
        let client = partial()
        #expect(client.format(7, "items") == "7 items")
        #expect(client.format(8, "items") == "overridden")
        formats.forwarded.verify()
        formats.stubbed.verify()
    }

    @Test func clientPresetOffersConfiguredControllersAndDirectTestValues() {
        let preset = makeClosureFieldClientPreset()
        let live = makeLiveClosureFieldClient()

        let failing = preset.failing { stub in
            stub.when { $0.version() }.thenReturn("configured")
        }
        #expect(failing().version() == "configured")
        failing.when { $0.version() }.verify()

        let stub = preset.stub { stub in
            stub.when {
                $0.format(Match.equal(2), Match.equal("items"))
            }.thenReturn("two items")
        }
        #expect(stub().format(2, "items") == "two items")

        let spy = preset.spy(forwardingTo: live) { spy in
            spy.when {
                $0.format(Match.equal(3), Match.any())
            }.thenReturn("three overridden")
        }
        #expect(spy().format(3, "items") == "three overridden")
        #expect(spy().version() == "live")
        #expect(spy.history.stubbed.callCount == 1)
        #expect(spy.history.forwarded.callCount == 1)

        let testValue = preset.testValue { stub in
            stub.when { $0.version() }.thenReturn("value")
        }
        #expect(testValue.version() == "value")

        let overriddenValue = preset.testValue(overriding: live) { spy in
            spy.when {
                $0.format(Match.equal(4), Match.any())
            }.thenReturn("four overridden")
        }
        #expect(overriddenValue.format(4, "items") == "four overridden")
        #expect(overriddenValue.version() == "live")

        let _: ClosureFieldClient = preset.testValue()
    }

    @Test func clientPresetConfiguresAsyncEndpointsInOneExpression() async throws {
        let preset = makeClosureFieldClientPreset()
        let live = makeLiveClosureFieldClient()

        let stub = await preset.failing { stub in
            await stub.when {
                await $0.lookup(Match.equal(9))
            }.thenReturn("nine")
            await stub.when(returning: [String]()) {
                try await $0.load(
                    Match.equal(9),
                    Match.equal("items")
                )
            }.thenReturn(["nine items"])
        }
        #expect(await stub().lookup(9) == "nine")
        #expect(try await stub().load(9, "items") == ["nine items"])

        let spy = await preset.spy(forwardingTo: live) { spy in
            await spy.when {
                await $0.lookup(Match.equal(10))
            }.thenReturn("ten overridden")
        }
        #expect(await spy().lookup(10) == "ten overridden")
        #expect(await spy().lookup(11) == "lookup-11")

        let testValue = await preset.testValue { stub in
            await stub.when {
                await $0.lookup(Match.equal(12))
            }.thenReturn("twelve")
        }
        #expect(await testValue.lookup(12) == "twelve")

        let overriddenValue = await preset.testValue(overriding: live) { spy in
            await spy.when {
                await $0.lookup(Match.equal(13))
            }.thenReturn("thirteen overridden")
        }
        #expect(await overriddenValue.lookup(13) == "thirteen overridden")
        #expect(await overriddenValue.lookup(14) == "lookup-14")
    }
}

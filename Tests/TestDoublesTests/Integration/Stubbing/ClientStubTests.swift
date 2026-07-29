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
}

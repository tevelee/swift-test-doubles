import Testing
import TestDoubles

private struct GeometryClient: Sendable {
    var area: @Sendable ((width: Int, height: Int)) -> Int
    var validate: @Sendable ((Int, Int)) throws -> Bool
    var load: @Sendable ((Int, String)) async -> String
    var fetch: @Sendable ((Int, String)) async throws -> String
}

private struct GeometryFailure: Error, Equatable {}

/// A closure field whose single parameter is a tuple uses the fixed-arity
/// endpoints; the variadic ones crash the Swift compiler for that shape.
@Suite struct ClientStubUnaryEndpointTests {
    private func makeStub() -> ClientStub<GeometryClient> {
        ClientStub<GeometryClient> { endpoints in
            GeometryClient(
                area: endpoints.unaryFunction("area"),
                validate: endpoints.unaryThrowingFunction("validate"),
                load: endpoints.unaryAsyncFunction("load"),
                fetch: endpoints.unaryAsyncThrowingFunction("fetch")
            )
        }
    }

    @Test func tupleParametersAreRecordedAsOneArgument() async throws {
        let geometry = makeStub()
        let areas = geometry.when { $0.area(Match.any()) }
        areas.then { (size: (width: Int, height: Int)) in size.width * size.height }
        geometry.when { try $0.validate(Match.any()) }.thenThrow(GeometryFailure())
        await geometry.when { await $0.load(Match.any()) }.thenReturn("loaded")
        await geometry.when { try await $0.fetch(Match.any()) }.thenReturn("fetched")

        let client = geometry()
        #expect(client.area((width: 3, height: 4)) == 12)
        #expect(throws: GeometryFailure()) { try client.validate((1, 2)) }
        #expect(await client.load((1, "a")) == "loaded")
        #expect(try await client.fetch((1, "a")) == "fetched")

        areas.verify()
        geometry.verify {
            $0.area(
                Match.matching(description: "3 by 4") { (size: (width: Int, height: Int)) in
                    size == (3, 4)
                }
            )
        }
    }
}

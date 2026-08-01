import Testing
import TestDoubles

/// Function-scoped protocols do not leave a discoverable linked witness in an
/// optimized client. Their source-level requirement references remain stable.
@Suite struct LocalProtocolDeclarationTests {
    @Test func functionLocalProtocolStubsAThrowingMethod() throws {
        protocol FileService {
            func read(path: String) throws -> String
        }

        let stub = try Stub<any FileService>(
            .method(signatureOf: FileService.read)
        )
        stub.when { try $0.read(path: Match.any()) }.thenReturn("contents")

        let sut: any FileService = stub()

        #expect(try sut.read(path: "/test") == "contents")
        stub.verify { try $0.read(path: Match.equal("/test")) }
    }

    @Test func functionLocalProtocolStubsAPropertyGetter() throws {
        protocol Counter {
            var count: Int { get }
        }

        let stub = try Stub<any Counter>(
            .getter(signatureOf: \Counter.count)
        )
        stub.when { $0.count }.thenReturn(7)

        #expect(stub().count == 7)
        stub.verify { $0.count }
    }

    @Test func functionLocalProtocolStubsAnAsyncMethod() async throws {
        protocol Loader {
            func load(id: Int) async throws -> String
        }

        let stub = try Stub<any Loader>(
            .method(signatureOf: Loader.load)
        )
        await stub.when { try await $0.load(id: Match.equal(3)) }.thenReturn("loaded")

        #expect(try await stub().load(id: 3) == "loaded")
        await stub.verify { try await $0.load(id: Match.equal(3)) }
    }

    @Test func closureLocalProtocolUsesItsSourceLevelRequirement() throws {
        let body: () throws -> Int = {
            protocol Pinger {
                func ping() -> Int
            }

            let stub = try Stub<any Pinger>(
                .method(signatureOf: Pinger.ping)
            )
            stub.when { $0.ping() }.thenReturn(42)
            return stub().ping()
        }

        #expect(try body() == 42)
    }

    @Test func methodLocalProtocolUsesItsSourceLevelRequirement() throws {
        #expect(try LocalProtocolHost.makeDouble() == "stubbed")
    }
}

private enum LocalProtocolHost {
    static func makeDouble() throws -> String {
        protocol Describer {
            func describe() -> String
        }

        let stub = try Stub<any Describer>(
            .method(signatureOf: Describer.describe)
        )
        stub.when { $0.describe() }.thenReturn("stubbed")
        return stub().describe()
    }
}

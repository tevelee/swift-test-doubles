import Foundation
import Testing
import TestDoubles

/// Requirements of a protocol declared inside a function, method, or closure
/// demangle with a trailing declaration context instead of a qualified name.
@Suite struct LocalProtocolDeclarationTests {
    @Test func functionLocalProtocolStubsAThrowingMethod() throws {
        protocol FileService {
            func read(path: String) throws -> Data
        }

        struct LinkedFileService: FileService {
            func read(path: String) throws -> Data { Data() }
        }

        let stub = try Stub<any FileService>()
        stub.when { try $0.read(path: Match.any()) }.thenReturn(Data([1, 2, 3]))

        let sut: any FileService = stub()

        #expect(try sut.read(path: "/test") == Data([1, 2, 3]))
        stub.verify { try $0.read(path: Match.equal("/test")) }
    }

    @Test func functionLocalProtocolStubsAPropertyGetter() throws {
        protocol Counter {
            var count: Int { get }
        }

        struct LinkedCounter: Counter {
            var count: Int { 0 }
        }

        let stub = try Stub<any Counter>()
        stub.when { $0.count }.thenReturn(7)

        #expect(stub().count == 7)
        stub.verify { $0.count }
    }

    @Test func functionLocalProtocolStubsAnAsyncMethod() async throws {
        protocol Loader {
            func load(id: Int) async throws -> String
        }

        struct LinkedLoader: Loader {
            func load(id: Int) async throws -> String { "" }
        }

        let stub = try Stub<any Loader>()
        await stub.when { try await $0.load(id: Match.equal(3)) }.thenReturn("loaded")

        #expect(try await stub().load(id: 3) == "loaded")
        await stub.verify { try await $0.load(id: Match.equal(3)) }
    }

    @Test func closureLocalProtocolIsDiscovered() throws {
        let body: () throws -> Int = {
            protocol Pinger {
                func ping() -> Int
            }

            struct LinkedPinger: Pinger {
                func ping() -> Int { 0 }
            }

            let stub = try Stub<any Pinger>()
            stub.when { $0.ping() }.thenReturn(42)
            return stub().ping()
        }

        #expect(try body() == 42)
    }

    @Test func methodLocalProtocolIsDiscovered() throws {
        #expect(try LocalProtocolHost.makeDouble() == "stubbed")
    }
}

private enum LocalProtocolHost {
    static func makeDouble() throws -> String {
        protocol Describer {
            func describe() -> String
        }

        struct LinkedDescriber: Describer {
            func describe() -> String { "" }
        }

        let stub = try Stub<any Describer>()
        stub.when { $0.describe() }.thenReturn("stubbed")
        return stub().describe()
    }
}

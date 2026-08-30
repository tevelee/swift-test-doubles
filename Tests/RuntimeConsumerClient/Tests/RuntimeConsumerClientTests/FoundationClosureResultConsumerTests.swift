import ConsumerFixtures
import Foundation
import TestDoubles
import Testing

@Suite struct FoundationClosureResultConsumerTests {
    @Test func closureArgumentTransportsThrowingDataResult() throws {
        let recordingLoader: ThrowingDataLoader = { _ in Data() }
        let stub = try Stub<any FoundationClosureArgumentSource>()
        stub.when {
            try $0.byteCount(
                using: Match.any(using: recordingLoader),
                path: Match.any()
            )
        }.thenEscaping { (loader: ThrowingDataLoader, path: String) throws in
            try loader(path).count
        }

        let actual = try stub().byteCount(
            using: { path in Data(path.utf8) },
            path: "fixture"
        )

        #expect(actual == 7)
    }

    @Test func returnedClosureTransportsThrowingDataResult() throws {
        let recordingLoader: ThrowingDataLoader = { _ in Data() }
        let expected = Data([2, 3, 5, 7])
        let stub = try Stub<any FoundationClosureResultSource>()
        stub.when(returning: recordingLoader) { $0.loader() }
            .thenReturn { path in
                path == "/fixture" ? expected : Data()
            }

        let loader = stub().loader()

        #expect(try loader("/fixture") == expected)
    }

    #if compiler(>=6.4)
        @Test func returnedAsyncClosureTransportsUUIDResult() async throws {
            let recordingLoader: AsyncIdentifierLoader = { _ in UUID() }
            let expected = UUID(
                uuidString: "00000000-0000-0000-0000-000000000263"
            )!
            let stub = try Stub<any AsyncFoundationClosureResultSource>()
            stub.when(returning: recordingLoader) { $0.loader() }
                .thenReturn { value in
                    value == 263 ? expected : UUID()
                }

            let loader = stub().loader()

            #expect(await loader(263) == expected)
        }
    #endif

    @Test func uncertainClosureParameterStillFailsClosed() {
        #expect(throws: Error.self) {
            _ = try Stub<any UncertainFoundationClosureParameterSource>()
        }
    }

    @Test func uncertainCustomClosureResultStillFailsClosed() {
        #expect(throws: Error.self) {
            _ = try Stub<any UncertainCustomClosureResultSource>()
        }
    }
}

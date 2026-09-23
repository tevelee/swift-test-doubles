import Testing
import TestDoubles

// Internal, not private: optimized builds must keep these conformances
// linked for automatic discovery.
struct StreamedCoordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct StreamEnvelope: Sendable {
    var stream: AsyncStream<Int>
    var label: String
}

protocol StreamingLocationService {
    func updates() -> AsyncStream<StreamedCoordinate>
    func labels() -> AsyncThrowingStream<String, any Error>
    func envelope() -> StreamEnvelope
    func count(_ stream: AsyncStream<Int>) async -> Int
}

struct LiveStreamingLocationService: StreamingLocationService {
    func updates() -> AsyncStream<StreamedCoordinate> { AsyncStream { $0.finish() } }
    func labels() -> AsyncThrowingStream<String, any Error> { AsyncThrowingStream { $0.finish() } }
    func envelope() -> StreamEnvelope { StreamEnvelope(stream: AsyncStream { $0.finish() }, label: "") }
    func count(_ stream: AsyncStream<Int>) async -> Int { 0 }
}

private struct StreamFailure: Error, Equatable {}

/// `AsyncStream` and other non-`@frozen` standard-library values are
/// address-only for every client, even though their reflected storage is a
/// single reference.
@Suite struct NonFrozenStandardLibraryValueTests {
    private func makeStub() throws -> Stub<any StreamingLocationService> {
        try Stub<any StreamingLocationService>(discoveringFrom: LiveStreamingLocationService())
    }

    @Test func asyncStreamResultsReachTheCaller() async throws {
        let stub = try makeStub()
        let controller = stub.whenStream { $0.updates() }.thenStream()
        let stream = stub().updates()

        controller.yield(StreamedCoordinate(latitude: 47.5, longitude: 19.0))
        controller.finish()

        var received: [StreamedCoordinate] = []
        for await coordinate in stream { received.append(coordinate) }
        #expect(received == [StreamedCoordinate(latitude: 47.5, longitude: 19.0)])
    }

    @Test func asyncThrowingStreamResultsPropagateFailures() async throws {
        let stub = try makeStub()
        let controller = stub.whenThrowingStream { $0.labels() }.thenThrowingStream()
        var iterator = stub().labels().makeAsyncIterator()

        controller.yield("ready")
        #expect(try await iterator.next() == "ready")
        controller.finish(throwing: StreamFailure())
        await #expect(throws: StreamFailure.self) { try await iterator.next() }
    }

    @Test func structsStoringAStreamAreReturnedIndirectly() async throws {
        let stub = try makeStub()
        stub.when { $0.envelope() }.thenReturn(
            StreamEnvelope(
                stream: AsyncStream {
                    $0.yield(7)
                    $0.finish()
                }, label: "sevens")
        )

        let envelope = stub().envelope()
        var values: [Int] = []
        for await value in envelope.stream { values.append(value) }

        #expect(envelope.label == "sevens")
        #expect(values == [7])
    }

    @Test func streamArgumentsReachHandlers() async throws {
        let stub = try makeStub()
        await stub.when { await $0.count(Match.any()) }
            .then { (stream: AsyncStream<Int>) async in
                var count = 0
                for await _ in stream { count += 1 }
                return count
            }

        let count = await stub().count(
            AsyncStream {
                $0.yield(1)
                $0.yield(2)
                $0.finish()
            })
        #expect(count == 2)
    }
}

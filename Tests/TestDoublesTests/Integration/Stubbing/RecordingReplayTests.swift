import Foundation
import Testing
@testable import TestDoubles

// Internal, not private: the conformer doubles as an automatic-discovery
// fixture, whose conformance record must stay reachable in release builds.
protocol RecordingReplayWeatherService: Sendable {
    func currentConditions(for city: String) throws -> String
    func forecast(for city: String) async throws -> [String]
}

struct RealRecordingReplayWeatherService: RecordingReplayWeatherService {
    func currentConditions(for city: String) throws -> String { "sunny in \(city)" }
    func forecast(for city: String) async throws -> [String] { ["sunny", "cloudy"] }
}

private struct RecordingReplayFailure: Error, Equatable {}

private final class SequencedResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String]

    init(_ responses: [String]) {
        self.responses = responses
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return responses.removeFirst()
    }
}

@Suite struct RecordingReplayTests {
    @Test func recordsAndReplaysASingleSynchronousCall() throws {
        let live = RealRecordingReplayWeatherService()
        let spy: Spy<any RecordingReplayWeatherService> = .make(forwardingTo: live)
        let session = RecordingSession()

        spy.when { try $0.currentConditions(for: any()) }
            .thenRecord(as: "currentConditions", into: session) { city in
                try live.currentConditions(for: city)
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        #expect(try recordedService.currentConditions(for: "Berlin") == "sunny in Berlin")

        let fixture = session.snapshot()
        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.when { try $0.currentConditions(for: any()) }
            .thenReplay(as: "currentConditions", from: fixture)

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "Berlin") == "sunny in Berlin")
        #expect(try replayedService.currentConditions(for: "anything") == "sunny in Berlin")
        stub.verify(.exactly(2)) { try $0.currentConditions(for: any()) }
    }

    @Test func replaysMultipleRecordedCallsInOrderThenRepeatsTheLast() throws {
        let responder = SequencedResponder([
            "sunny in Berlin", "sunny in Vienna", "sunny in Prague"
        ])

        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        let session = RecordingSession()
        spy.when { try $0.currentConditions(for: any()) }
            .thenRecord(as: "currentConditions", into: session) { (_: String) in
                responder.next()
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        for _ in 0 ..< 3 {
            _ = try recordedService.currentConditions(for: "ignored")
        }

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.when { try $0.currentConditions(for: any()) }
            .thenReplay(as: "currentConditions", from: session.snapshot())

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Berlin")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Vienna")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Prague")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Prague")
    }

    @Test func recordsAndReplaysAnAsynchronousCall() async throws {
        let live = RealRecordingReplayWeatherService()
        let spy: Spy<any RecordingReplayWeatherService> = .make(forwardingTo: live)
        let session = RecordingSession()

        await spy.when { try await $0.forecast(for: any()) }
            .thenRecord(as: "forecast", into: session) { city in
                try await live.forecast(for: city)
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        #expect(try await recordedService.forecast(for: "Berlin") == ["sunny", "cloudy"])

        let stub = try Stub<any RecordingReplayWeatherService>()
        await stub.when { try await $0.forecast(for: any()) }
            .thenReplay(as: "forecast", from: session.snapshot())

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try await replayedService.forecast(for: "Berlin") == ["sunny", "cloudy"])
    }

    @Test func fixtureRoundTripsThroughDisk() throws {
        let live = RealRecordingReplayWeatherService()
        let spy: Spy<any RecordingReplayWeatherService> = .make(forwardingTo: live)
        let session = RecordingSession()
        spy.when { try $0.currentConditions(for: any()) }
            .thenRecord(as: "currentConditions", into: session) { city in
                try live.currentConditions(for: city)
            }
        _ = try (spy() as any RecordingReplayWeatherService).currentConditions(for: "Berlin")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-replay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try session.save(to: url)

        let loaded = try InteractionFixture.load(from: url)
        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.when { try $0.currentConditions(for: any()) }
            .thenReplay(as: "currentConditions", from: loaded)

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "Berlin") == "sunny in Berlin")
    }

    @Test func thrownErrorsAreNotRecorded() throws {
        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        let session = RecordingSession()
        spy.when { try $0.currentConditions(for: any()) }
            .thenRecord(as: "currentConditions", into: session) { (_: String) -> String in
                throw RecordingReplayFailure()
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        #expect(throws: RecordingReplayFailure.self) {
            try recordedService.currentConditions(for: "Berlin")
        }
        let recorded: [String] = session.snapshot().decodedResults(
            as: "currentConditions",
            resultType: String.self
        )
        #expect(recorded.isEmpty)
    }
}

#if compiler(>=6.2) && (os(macOS) || os(Linux) || targetEnvironment(macCatalyst))
    @Suite struct RecordingReplayExitTests {
        @Test func replayingAMissingKeyFailsClosed() async throws {
            let result = try await #require(
                processExitsWith: .failure,
                observing: [\.standardErrorContent]
            ) {
                let stub = try Stub<any RecordingReplayWeatherService>()
                stub.when { try $0.currentConditions(for: any()) }
                    .thenReplay(as: "never-recorded", from: InteractionFixture())
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("no recorded calls"))
            #expect(diagnostic.contains("never-recorded"))
        }
    }
#endif

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

private struct RecordingReplayFailure: Error, Codable, Equatable, Sendable {}

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

        spy.onCall { try $0.currentConditions(for: Match.any()) }
            .thenRecord(as: "currentConditions", into: session) { city in
                try live.currentConditions(for: city)
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        #expect(try recordedService.currentConditions(for: "Berlin") == "sunny in Berlin")

        let fixture = session.snapshot()
        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(as: "currentConditions", from: fixture)

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "Berlin") == "sunny in Berlin")
        #expect(try replayedService.currentConditions(for: "anything") == "sunny in Berlin")
        stub.verify(.exactly(2)) { try $0.currentConditions(for: Match.any()) }
    }

    @Test func replaysMultipleRecordedCallsInOrderThenRepeatsTheLast() throws {
        let responder = SequencedResponder([
            "sunny in Berlin", "sunny in Vienna", "sunny in Prague"
        ])

        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        let session = RecordingSession()
        spy.onCall { try $0.currentConditions(for: Match.any()) }
            .thenRecord(as: "currentConditions", into: session) { (_: String) in
                responder.next()
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        for _ in 0 ..< 3 {
            _ = try recordedService.currentConditions(for: "ignored")
        }

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(as: "currentConditions", from: session.snapshot())

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Berlin")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Vienna")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Prague")
        #expect(try replayedService.currentConditions(for: "x") == "sunny in Prague")
    }

    @Test func replaysResponsesMatchedToRecordedRequests() throws {
        let session = RecordingSession()
        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        spy.onCall { try $0.currentConditions(for: Match.any()) }
            .thenRecord(as: "currentConditions", into: session, recording: { (city: String) in city }) { city in
                "weather:\(city)"
            }
        let recordedService: any RecordingReplayWeatherService = spy()
        _ = try recordedService.currentConditions(for: "Berlin")
        _ = try recordedService.currentConditions(for: "Vienna")

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(
                as: "currentConditions",
                from: session.snapshot(),
                matching: { (city: String) in city }
            )
        let replayedService: any RecordingReplayWeatherService = stub()

        #expect(try replayedService.currentConditions(for: "Vienna") == "weather:Vienna")
        #expect(try replayedService.currentConditions(for: "Berlin") == "weather:Berlin")
    }

    @Test func recordsAndReplaysAnAsynchronousCall() async throws {
        let live = RealRecordingReplayWeatherService()
        let spy: Spy<any RecordingReplayWeatherService> = .make(forwardingTo: live)
        let session = RecordingSession()

        await spy.onCall { try await $0.forecast(for: Match.any()) }
            .thenRecord(as: "forecast", into: session) { city in
                try await live.forecast(for: city)
            }

        let recordedService: any RecordingReplayWeatherService = spy()
        #expect(try await recordedService.forecast(for: "Berlin") == ["sunny", "cloudy"])

        let stub = try Stub<any RecordingReplayWeatherService>()
        await stub.onCall { try await $0.forecast(for: Match.any()) }
            .thenReplay(as: "forecast", from: session.snapshot())

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try await replayedService.forecast(for: "Berlin") == ["sunny", "cloudy"])
    }

    @Test func fixtureRoundTripsThroughDisk() throws {
        let live = RealRecordingReplayWeatherService()
        let spy: Spy<any RecordingReplayWeatherService> = .make(forwardingTo: live)
        let session = RecordingSession()
        spy.onCall { try $0.currentConditions(for: Match.any()) }
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
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(as: "currentConditions", from: loaded)

        let replayedService: any RecordingReplayWeatherService = stub()
        #expect(try replayedService.currentConditions(for: "Berlin") == "sunny in Berlin")
    }

    @Test func replaysRecordedSuccessesAndErrors() throws {
        let session = RecordingSession()
        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        spy.onCall { try $0.currentConditions(for: Match.any()) }
            .thenRecord(
                as: "currentConditions",
                into: session,
                recordingErrorsAs: RecordingReplayFailure.self
            ) { city in
                if city == "missing" { throw RecordingReplayFailure() }
                return "weather:\(city)"
            }
        let recorded: any RecordingReplayWeatherService = spy()
        #expect(try recorded.currentConditions(for: "Berlin") == "weather:Berlin")
        #expect(throws: RecordingReplayFailure.self) {
            try recorded.currentConditions(for: "missing")
        }

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(
                as: "currentConditions",
                from: session.snapshot(),
                throwing: RecordingReplayFailure.self
            )
        let replayed: any RecordingReplayWeatherService = stub()
        #expect(try replayed.currentConditions(for: "anything") == "weather:Berlin")
        #expect(throws: RecordingReplayFailure.self) {
            try replayed.currentConditions(for: "anything")
        }
    }

    @Test func redactsRecordedRequestsBeforeInputMatchedReplay() throws {
        let redactor = FixtureRedactor { _, role, data in
            role == .request ? Data("\"redacted\"".utf8) : data
        }
        let session = RecordingSession(redacting: redactor)
        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        spy.onCall { try $0.currentConditions(for: Match.any()) }
            .thenRecord(as: "currentConditions", into: session, recording: { (city: String) in city }) { city in
                "weather:\(city)"
            }
        _ = try (spy() as any RecordingReplayWeatherService).currentConditions(for: "Berlin")

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(
                as: "currentConditions",
                from: session.snapshot(),
                matching: { (city: String) in city },
                redacting: redactor
            )
        #expect(
            try (stub() as any RecordingReplayWeatherService)
                .currentConditions(for: "not-a-secret") == "weather:Berlin"
        )
    }

    @Test func loadsVersionOneFixturesAndMigratesThemInMemory() throws {
        let result = try JSONEncoder().encode("legacy result")
        let legacy = try JSONSerialization.data(
            withJSONObject: ["entries": ["currentConditions": [result.base64EncodedString()]]]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-replay-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try legacy.write(to: url)

        let stub = try Stub<any RecordingReplayWeatherService>()
        stub.onCall { try $0.currentConditions(for: Match.any()) }
            .thenReplay(as: "currentConditions", from: try InteractionFixture.load(from: url))
        #expect(
            try (stub() as any RecordingReplayWeatherService)
                .currentConditions(for: "Berlin") == "legacy result"
        )
    }

    @Test(arguments: [0, InteractionFixture.currentSchemaVersion + 1])
    func rejectsUnsupportedFixtureSchemaVersions(_ version: Int) throws {
        let encoded = try JSONSerialization.data(
            withJSONObject: ["schemaVersion": version, "outcomes": [:]]
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(InteractionFixture.self, from: encoded)
        }
    }

    @Test func thrownErrorsAreNotRecorded() throws {
        let spy: Spy<any RecordingReplayWeatherService> = .make(
            forwardingTo: RealRecordingReplayWeatherService()
        )
        let session = RecordingSession()
        spy.onCall { try $0.currentConditions(for: Match.any()) }
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
                stub.onCall { try $0.currentConditions(for: Match.any()) }
                    .thenReplay(as: "never-recorded", from: InteractionFixture())
            }
            let diagnostic = try requireStandardErrorDiagnostic(from: result)
            #expect(diagnostic.contains("no recorded calls"))
            #expect(diagnostic.contains("never-recorded"))
        }
    }
#endif

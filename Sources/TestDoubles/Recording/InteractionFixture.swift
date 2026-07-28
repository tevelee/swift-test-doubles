import Foundation

/// An immutable, `Codable` log of results recorded by
/// ``RecordingSession``, keyed by the label each ``StubBuilder/thenRecord(as:into:calling:)-62gmo``
/// registration recorded them under.
///
/// Persist a fixture once, alongside the test that recorded it, then replay
/// it wherever the real dependency should not run:
///
/// ```swift
/// let fixture = try InteractionFixture.load(from: fixtureURL)
/// let stub = try Stub<any WeatherService>()
/// stub.when { try await $0.currentConditions(for: any()) }
///     .thenReplay(as: "currentConditions", from: fixture)
///
/// let service: any WeatherService = stub()
/// try await service.currentConditions(for: "Berlin") // the recorded value
/// ```
public struct InteractionFixture: Codable, Sendable {
    private var entries: [String: [Data]]
    private var requests: [String: [Data?]]?

    init(entries: [String: [Data]], requests: [String: [Data?]]? = nil) {
        self.entries = entries
        self.requests = requests
    }

    /// Creates an empty fixture. Useful only as a placeholder; a real fixture
    /// comes from ``RecordingSession/snapshot()`` or ``load(from:)``.
    public init() {
        entries = [:]
        requests = nil
    }

    /// Loads a fixture previously written with ``save(to:)`` or
    /// ``RecordingSession/save(to:)``.
    public static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    /// Writes this fixture as JSON, loadable later with ``load(from:)``.
    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url)
    }

    func decodedResults<Value: Decodable>(as key: String, resultType: Value.Type) -> [Value] {
        guard let dataEntries = entries[key] else { return [] }
        return dataEntries.map { data in
            guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
                fatalError(
                    "[TestDoubles] Could not decode a recorded '\(key)' result as \(Value.self). The fixture may have been recorded against a different result type."
                )
            }
            return value
        }
    }

    func decodedResults<Value: Decodable, Request: Encodable>(
        as key: String,
        matching request: Request,
        resultType: Value.Type
    ) -> (requestData: Data, values: [Value]) {
        guard let requestEntries = requests?[key], let resultEntries = entries[key] else {
            fatalError(
                "[TestDoubles] Fixture has no request data under '\(key)'. Record it with thenRecord(as:into:recording:calling:) before using input-matched replay."
            )
        }
        let encodedRequest = encode(request, as: key, role: "request")
        let values = zip(requestEntries, resultEntries).compactMap { pair -> Value? in
            let (requestData, resultData) = pair
            guard requestData == encodedRequest else { return nil }
            guard let value = try? JSONDecoder().decode(Value.self, from: resultData) else {
                fatalError(
                    "[TestDoubles] Could not decode a recorded '\(key)' result as \(Value.self). The fixture may have been recorded against a different result type."
                )
            }
            return value
        }
        return (encodedRequest, values)
    }

    private func encode<Value: Encodable>(_ value: Value, as key: String, role: String) -> Data {
        guard let data = try? JSONEncoder().encode(value) else {
            fatalError(
                "[TestDoubles] Could not encode the \(role) for recorded '\(key)' calls as JSON."
            )
        }
        return data
    }
}

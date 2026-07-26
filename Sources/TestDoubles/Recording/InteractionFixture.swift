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

    init(entries: [String: [Data]]) {
        self.entries = entries
    }

    /// Creates an empty fixture. Useful only as a placeholder; a real fixture
    /// comes from ``RecordingSession/snapshot()`` or ``load(from:)``.
    public init() {
        entries = [:]
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
}

import Foundation

/// Selects the serialized fixture value being transformed by a
/// ``FixtureRedactor``.
public enum FixtureValueRole: Sendable {
    /// An encoded request used for input-matched replay.
    case request
    /// An encoded successful result.
    case result
    /// An encoded error captured from a throwing requirement.
    case error
}

/// Transforms serialized fixture values before they are persisted.
///
/// Supply the same redactor to input-matched replay that you supplied to the
/// recording session. This allows tests to omit secrets while retaining a
/// deterministic request identity, for example by replacing a bearer token
/// with a fixed placeholder.
public struct FixtureRedactor: @unchecked Sendable {
    private let transform: @Sendable (String, FixtureValueRole, Data) -> Data

    /// A redactor that preserves every encoded value unchanged.
    public static let none = Self { _, _, data in data }

    /// Creates a redactor applied to every serialized fixture value.
    public init(
        _ transform: @escaping @Sendable (String, FixtureValueRole, Data) -> Data
    ) {
        self.transform = transform
    }

    func apply(_ data: Data, as key: String, role: FixtureValueRole) -> Data {
        transform(key, role, data)
    }
}

/// An immutable, `Codable` log of responses recorded by ``RecordingSession``.
///
/// Fixtures use a versioned schema. ``load(from:)`` transparently migrates the
/// original result-only format, so committed fixtures remain valid as support
/// for requests and recorded errors evolves.
public struct InteractionFixture: Codable, Sendable {
    /// The schema written by the current library version.
    public static let currentSchemaVersion = 2

    private var schemaVersion: Int
    private var outcomes: [String: [FixtureOutcome]]
    private var requests: [String: [Data?]]?

    init(outcomes: [String: [FixtureOutcome]], requests: [String: [Data?]]? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.outcomes = outcomes
        self.requests = requests
    }

    /// Creates an empty fixture. Useful only as a placeholder; a real fixture
    /// comes from ``RecordingSession/snapshot()`` or ``load(from:)``.
    public init() {
        schemaVersion = Self.currentSchemaVersion
        outcomes = [:]
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
        guard let recorded = outcomes[key] else { return [] }
        return recorded.map { outcome in
            guard let data = outcome.result else {
                fatalError(
                    "[TestDoubles] Fixture recorded an error for '\(key)'. Use thenReplay(as:from:throwing:) to replay errors."
                )
            }
            return decode(data, as: Value.self, key: key, role: "result")
        }
    }

    func decodedResults<Value: Decodable, Request: Encodable>(
        as key: String,
        matching request: Request,
        redacting redactor: FixtureRedactor = .none,
        resultType: Value.Type
    ) -> (requestData: Data, values: [Value]) {
        guard let requestEntries = requests?[key], let recorded = outcomes[key] else {
            fatalError(
                "[TestDoubles] Fixture has no request data under '\(key)'. Record it with thenRecord(as:into:recording:calling:) before using input-matched replay."
            )
        }
        let encodedRequest = redactor.apply(
            encode(request, as: key, role: "request"),
            as: key,
            role: .request
        )
        let values = zip(requestEntries, recorded).compactMap { pair -> Value? in
            let (requestData, outcome) = pair
            guard requestData == encodedRequest else { return nil }
            guard let data = outcome.result else {
                fatalError(
                    "[TestDoubles] Fixture recorded an error for '\(key)'. Use thenReplay(as:from:throwing:) to replay errors."
                )
            }
            return decode(data, as: Value.self, key: key, role: "result")
        }
        return (encodedRequest, values)
    }

    func decodedOutcomes<Value: Decodable, Failure: Error & Decodable>(
        as key: String,
        resultType: Value.Type,
        failureType: Failure.Type
    ) -> [Result<Value, Failure>] {
        guard let recorded = outcomes[key] else { return [] }
        return recorded.map { outcome in
            if let data = outcome.result {
                return .success(decode(data, as: Value.self, key: key, role: "result"))
            }
            guard let data = outcome.error else {
                fatalError("[TestDoubles] Fixture entry '\(key)' has neither a result nor an error.")
            }
            return .failure(decode(data, as: Failure.self, key: key, role: "error"))
        }
    }

    private func decode<Value: Decodable>(
        _ data: Data,
        as type: Value.Type,
        key: String,
        role: String
    ) -> Value {
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            fatalError(
                "[TestDoubles] Could not decode a recorded '\(key)' \(role) as \(Value.self). The fixture may have been recorded against a different type."
            )
        }
        return value
    }

    private func encode<Value: Encodable>(_ value: Value, as key: String, role: String) -> Data {
        guard let data = try? JSONEncoder().encode(value) else {
            fatalError("[TestDoubles] Could not encode the \(role) for recorded '\(key)' calls as JSON.")
        }
        return data
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case outcomes
        case requests
        // Version 1 used `entries` for result-only recordings.
        case entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1 ... Self.currentSchemaVersion).contains(version) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription:
                    "Unsupported interaction fixture schema version \(version); "
                    + "supported versions are 1...\(Self.currentSchemaVersion)."
            )
        }
        requests = try container.decodeIfPresent([String: [Data?]].self, forKey: .requests)
        if version >= Self.currentSchemaVersion,
            let decoded = try container.decodeIfPresent([String: [FixtureOutcome]].self, forKey: .outcomes)
        {
            outcomes = decoded
        } else {
            let legacy = try container.decode([String: [Data]].self, forKey: .entries)
            outcomes = legacy.mapValues { $0.map(FixtureOutcome.success) }
        }
        // Decoding is the migration boundary: every in-memory fixture follows
        // today's schema even when the persisted input was an earlier version.
        schemaVersion = Self.currentSchemaVersion
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(outcomes, forKey: .outcomes)
        try container.encodeIfPresent(requests, forKey: .requests)
    }
}

struct FixtureOutcome: Codable, Sendable {
    let result: Data?
    let error: Data?

    static func success(_ result: Data) -> Self {
        Self(result: result, error: nil)
    }

    static func failure(_ error: Data) -> Self {
        Self(result: nil, error: error)
    }
}

import Foundation

/// Captures results produced by ``CallPattern/thenRecord(as:into:calling:)-2d9h6``
/// so they can be replayed later with ``CallPattern/thenReplay(as:from:)``.
///
/// Attach one session to a `Spy` wrapping a real dependency, record a test
/// pass against the real thing, then freeze it into an ``InteractionFixture``
/// with ``snapshot()`` or ``save(to:)``. A session accepts concurrent
/// recordings from calls dispatched on different tasks.
///
/// ```swift
/// let live = LiveWeatherService()
/// let spy: Spy<any WeatherService> = .make(forwardingTo: live)
/// let session = RecordingSession()
///
/// spy.onCall { try await $0.currentConditions(for: Match.any()) }
///     .thenRecord(as: "currentConditions", into: session) { city in
///         try await live.currentConditions(for: city)
///     }
///
/// _ = try await spy().currentConditions(for: "Berlin")
/// try session.save(to: fixtureURL)
/// ```
public final class RecordingSession: @unchecked Sendable {
    private let lock = NSLock()
    private let redactor: FixtureRedactor
    private var outcomes: [String: [FixtureOutcome]] = [:]
    private var requests: [String: [Data?]] = [:]

    /// Creates a session with nothing recorded yet.
    ///
    /// Pass a redactor to remove or normalize sensitive serialized fields
    /// before they reach a fixture. Use the same redactor with
    /// input-matched replay.
    public init(redacting redactor: FixtureRedactor = .none) {
        self.redactor = redactor
    }

    func recordSuccess<Value: Encodable>(_ value: Value, as key: String) {
        recordSuccess(value, requestData: nil, as: key)
    }

    func recordSuccess<Value: Encodable, Request: Encodable>(
        _ value: Value,
        recording request: Request,
        as key: String
    ) {
        guard let requestData = try? JSONEncoder().encode(request) else {
            fatalError(
                "[TestDoubles] Could not encode the request for recorded '\(key)' calls as JSON."
            )
        }
        recordSuccess(value, requestData: requestData, as: key)
    }

    func recordFailure<Failure: Error & Encodable>(_ error: Failure, as key: String) {
        guard let data = try? JSONEncoder().encode(error) else {
            fatalError(
                "[TestDoubles] Could not encode a recorded '\(key)' error of type \(Failure.self) as JSON. Recorded errors must round-trip through JSONEncoder."
            )
        }
        append(
            .failure(redactor.apply(data, as: key, role: .error)),
            requestData: nil,
            as: key
        )
    }

    private func recordSuccess<Value: Encodable>(
        _ value: Value,
        requestData: Data?,
        as key: String
    ) {
        guard let data = try? JSONEncoder().encode(value) else {
            fatalError(
                "[TestDoubles] Could not encode a recorded '\(key)' result of type \(Value.self) as JSON. Recorded result types must round-trip through JSONEncoder."
            )
        }
        let redactedRequest = requestData.map { redactor.apply($0, as: key, role: .request) }
        append(
            .success(redactor.apply(data, as: key, role: .result)),
            requestData: redactedRequest,
            as: key
        )
    }

    private func append(_ outcome: FixtureOutcome, requestData: Data?, as key: String) {
        lock.lock()
        outcomes[key, default: []].append(outcome)
        requests[key, default: []].append(requestData)
        lock.unlock()
    }

    /// Freezes the calls recorded so far into an immutable, `Codable` fixture.
    ///
    /// Later recordings on this session do not affect a snapshot already
    /// taken.
    public func snapshot() -> InteractionFixture {
        lock.lock()
        defer { lock.unlock() }
        return InteractionFixture(outcomes: outcomes, requests: requests)
    }

    /// Freezes the calls recorded so far and writes them as JSON to `url`,
    /// loadable later with ``InteractionFixture/load(from:)``.
    public func save(to url: URL) throws {
        try snapshot().save(to: url)
    }
}

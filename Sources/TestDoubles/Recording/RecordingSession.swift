import Foundation

/// Captures results produced by ``StubBuilder/thenRecord(as:into:calling:)-62gmo``
/// so they can be replayed later with ``StubBuilder/thenReplay(as:from:)``.
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
/// spy.when { try await $0.currentConditions(for: any()) }
///     .thenRecord(as: "currentConditions", into: session) { city in
///         try await live.currentConditions(for: city)
///     }
///
/// _ = try await spy().currentConditions(for: "Berlin")
/// try session.save(to: fixtureURL)
/// ```
public final class RecordingSession: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: [Data]] = [:]

    public init() {}

    func recordSuccess<Value: Encodable>(_ value: Value, as key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            fatalError(
                "[TestDoubles] Could not encode a recorded '\(key)' result of type \(Value.self) as JSON. Recorded result types must round-trip through JSONEncoder."
            )
        }
        lock.lock()
        entries[key, default: []].append(data)
        lock.unlock()
    }

    /// Freezes the calls recorded so far into an immutable, `Codable` fixture.
    ///
    /// Later recordings on this session do not affect a snapshot already
    /// taken.
    public func snapshot() -> InteractionFixture {
        lock.lock()
        defer { lock.unlock() }
        return InteractionFixture(entries: entries)
    }

    /// Freezes the calls recorded so far and writes them as JSON to `url`,
    /// loadable later with ``InteractionFixture/load(from:)``.
    public func save(to url: URL) throws {
        try snapshot().save(to: url)
    }
}

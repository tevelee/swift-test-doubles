/// A runtime-generated test double that must not be used by the code under test.
///
/// Use a dummy when an API requires a protocol value but the exercised code
/// path is not expected to invoke it. `Dummy` reflects the protocol layout at
/// runtime and fabricates a conforming value without behavior, call recording,
/// or verification.
///
/// ```swift
/// let result = feature.run(analytics: makeDummy(AnalyticsClient.self))
/// ```
///
/// Invoking any protocol requirement on the generated value terminates the
/// process with a diagnostic identifying the declaring protocol and witness
/// requirement. This fail-closed behavior exposes an incorrect dummy as a test
/// bug instead of inventing a result.
public final class Dummy<P> {
    private let storage: FabricatedExistentialStorage<P>

    struct PreparedDummy {
        let storage: FabricatedExistentialStorage<P>
    }

    init(prepared: PreparedDummy) {
        storage = prepared.storage
    }

    /// Creates a dummy generator for a protocol existential using its runtime metadata.
    ///
    /// - Throws: ``StubError`` when the protocol layout cannot be fabricated safely.
    public convenience init() throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Stub<P>.prepareDummy()
        }
        self.init(prepared: prepared)
    }

    /// Returns the generated protocol existential.
    public func callAsFunction() -> P {
        storage.materialize()
    }
}

/// A dummy is safe to share only when the protocol existential it produces is
/// itself safe to transfer between concurrency domains.
extension Dummy: @unchecked Sendable where P: Sendable {}

/// Returns a runtime-generated dummy value for `protocolType`.
///
/// Use a dummy when an API requires a protocol value but the exercised code
/// path must not invoke it. Construction terminates the process with a
/// diagnostic if the protocol layout cannot be fabricated safely.
///
/// - Parameter protocolType: The protocol metatype that determines the returned existential.
/// - Returns: A protocol value with no behavior, call recording, or verification.
public func makeDummy<P>(_ protocolType: P.Type = P.self) -> P {
    constructTestDoubleOrFail(.dummy, for: protocolType) { () throws(StubError) -> P in
        try Dummy<P>()()
    }
}

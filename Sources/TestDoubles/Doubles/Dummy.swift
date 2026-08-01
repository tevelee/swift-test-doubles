/// A generated placeholder value that must not be used by the code under test.
///
/// Use a dummy when an API requires a value but the exercised code path is not
/// expected to use it. `Dummy` synthesizes valid placeholder values for common
/// concrete types and recursively constructible aggregates. For protocol
/// existentials, it reflects the protocol layout at runtime and fabricates a
/// conforming value without behavior, call recording, or verification.
///
/// ```swift
/// let result = feature.run(analytics: Dummy.make(AnalyticsClient.self))
/// ```
///
/// Invoking any protocol requirement on a generated existential terminates the
/// process with a diagnostic identifying the declaring protocol and witness
/// requirement. Concrete dummy contents are unspecified and must not be read.
public final class Dummy<P> {
    private enum Storage {
        case concrete(P)
        case protocolExistential(RuntimeStubFactory.Storage<P>)
    }

    private let storage: Storage

    struct PreparedDummy {
        let storage: RuntimeStubFactory.Storage<P>
    }

    init(prepared: PreparedDummy) {
        storage = .protocolExistential(prepared.storage)
    }

    private init(value: P) {
        storage = .concrete(value)
    }

    /// Creates a dummy generator for `P`.
    ///
    /// Common concrete values are synthesized as valid placeholders. Protocol
    /// existentials are fabricated from their runtime metadata.
    ///
    /// - Throws: ``StubError`` when `P` cannot be fabricated safely.
    public convenience init() throws(StubError) {
        if let value = RuntimeStubFactory.makeRecordingPlaceholder(for: P.self) {
            self.init(value: value)
            return
        }

        do {
            let prepared = try withStubConstructionError(for: P.self) {
                try Stub<P>.prepareDummy()
            }
            self.init(prepared: prepared)
        } catch let error {
            guard case .typeIsNotProtocol = error else { throw error }
            throw .dummyValueNotSynthesizable(typeDescription: String(reflecting: P.self))
        }
    }

    /// Creates a dummy generator using a caller-supplied valid placeholder.
    ///
    /// Use this initializer for classes, payload-only enums, and concrete types
    /// whose invariants prevent automatic synthesis. The factory runs once
    /// during initialization.
    public convenience init(using makeValue: () -> P) {
        self.init(value: makeValue())
    }

    /// Returns the generated dummy value.
    public func callAsFunction() -> P {
        switch storage {
            case .concrete(let value):
                value
            case .protocolExistential(let storage):
                storage.materialize()
        }
    }
}

/// A dummy is safe to share only when the protocol existential it produces is
/// itself safe to transfer between concurrency domains.
extension Dummy: @unchecked Sendable where P: Sendable {}

extension Dummy {
    /// Returns a generated dummy value for `type`.
    ///
    /// Common concrete values are synthesized as valid placeholders. Protocol
    /// existentials use fail-closed runtime-generated conformances. Construction
    /// terminates the process with a diagnostic when the type cannot be
    /// fabricated safely; use ``make(_:using:)`` for such concrete types.
    ///
    /// - Parameter type: The type of value to return.
    /// - Returns: A placeholder with unspecified contents that must not be used.
    public static func make(_ type: P.Type = P.self) -> P {
        constructTestDoubleOrFail(.dummy, for: type) { () throws(StubError) -> P in
            try Dummy<P>()()
        }
    }

    /// Returns a caller-supplied valid placeholder as a dummy value.
    ///
    /// Use this overload for a concrete type that cannot be synthesized safely,
    /// such as a class without a generally available initializer or an enum
    /// whose every case carries a payload.
    public static func make(
        _ type: P.Type = P.self,
        using makeValue: () -> P
    ) -> P {
        _ = type
        return makeValue()
    }
}

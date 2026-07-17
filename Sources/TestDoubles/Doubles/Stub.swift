/// A runtime-generated test double for a protocol existential.
///
/// Use the throwing initializer without requirements when signatures are
/// discoverable from a linked conformer or resilient protocol descriptors.
/// Supply ``Requirement`` values when neither runtime source is available.
///
/// ```swift
/// let stub = try Stub<any Calculator>()
/// stub.when { $0.add(1, 2) }.thenReturn(42)
///
/// let calculator: any Calculator = stub()
/// ```
public final class Stub<P> {
    let recorder: StubRecorder
    private let storage: FabricatedExistentialStorage<P>

    struct PreparedStub {
        let recorder: StubRecorder
        let storage: FabricatedExistentialStorage<P>
    }

    init(prepared: PreparedStub) {
        self.recorder = prepared.recorder
        self.storage = prepared.storage
    }

    /// Creates a stub from runtime-discovered or explicitly supplied
    /// requirement signatures.
    ///
    /// With no arguments, the stub discovers signatures from existing
    /// conformer witness tables or exported resilient-protocol requirement
    /// descriptors. Flat explicit requirements remove that dependency for a
    /// single-root protocol and must appear in protocol requirement order. Use
    /// `init(requirementsByProtocol:)` for multi-root compositions. Linked
    /// witnesses and resilient requirement symbols also validate every
    /// reliably discoverable explicit signature component.
    public convenience init(_ requirements: Requirement...) throws {
        let prepared =
            if requirements.isEmpty {
                try Self.prepare()
            } else {
                try Self.prepare(requirements: requirements)
            }
        self.init(prepared: prepared)
    }

    /// Creates a stub for an unbound protocol existential using caller-supplied
    /// associated-type bindings.
    ///
    /// Supply exactly one binding for every associated type in the complete
    /// protocol layout. Requirements may use those bindings only in covariant
    /// result positions. With no explicit requirements, signatures are still
    /// discovered from a linked conformer or resilient protocol descriptors.
    public convenience init(
        associatedTypes: [AssociatedTypeBinding],
        _ requirements: Requirement...
    ) throws {
        self.init(
            prepared: try Self.prepare(
                callerAssociatedTypeBindings: associatedTypes,
                requirements: requirements
            ))
    }

    /// Creates a single-root protocol stub using automatic signature discovery
    /// plus one throwing-effect hint for each getter.
    ///
    /// Supply effects in base-first, depth-first getter declaration order;
    /// methods, initializers, and setters do not consume an entry. Every getter
    /// must have a hint because Swift runtime metadata does not distinguish a
    /// synchronous nonthrowing getter from a synchronous throwing getter. Use
    /// `init(getterEffectsByProtocol:)` to scope effects by their declaring
    /// protocol in inheritance graphs or compositions.
    public convenience init(
        getterEffects firstEffect: GetterEffect,
        _ additionalEffects: GetterEffect...
    ) throws {
        self.init(
            prepared: try Self.prepare(
                getterEffects: [firstEffect] + additionalEffects
            ))
    }

    /// Creates a stub using getter-effect hints grouped by their declaring protocols.
    ///
    /// Use this initializer for inheritance graphs and protocol compositions.
    /// Group order does not matter. Supply one group for every protocol that
    /// directly declares a getter; inherited getters belong to their original
    /// declaring protocol.
    public convenience init(
        getterEffectsByProtocol firstGroup: ProtocolGetterEffects,
        _ additionalGroups: ProtocolGetterEffects...
    ) throws {
        self.init(
            prepared: try Self.prepare(
                getterEffectGroups: [firstGroup] + additionalGroups
            ))
    }

    /// Creates a stub using explicit requirements grouped by their declaring
    /// protocols.
    ///
    /// Use this initializer for protocol compositions. Group order does not
    /// matter. Supply one group for every protocol that directly declares a
    /// callable requirement; inherited requirements belong to their original
    /// declaring protocol.
    public convenience init(
        requirementsByProtocol firstGroup: ProtocolRequirements,
        _ additionalGroups: ProtocolRequirements...
    ) throws {
        self.init(
            prepared: try Self.prepare(
                requirementGroups: [firstGroup] + additionalGroups
            ))
    }

    /// Creates a stub from an array of requirements grouped by declaring
    /// protocol. This form also supports protocols that declare no callable
    /// requirements by accepting an empty array.
    public convenience init(
        requirementsByProtocol groups: [ProtocolRequirements]
    ) throws {
        self.init(prepared: try Self.prepare(requirementGroups: groups))
    }

    /// Returns the generated protocol existential.
    public func callAsFunction() -> P {
        materializeUnchecked()
    }

    func materializeForRecording() -> P {
        materializeUnchecked()
    }

    private func materializeUnchecked() -> P {
        storage.materialize()
    }

    private func withMaterializedValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let value = materializeUnchecked()
        defer { withExtendedLifetime(value) {} }
        return try operation(value)
    }

    private func withMaterializedValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        let value = materializeUnchecked()
        defer { withExtendedLifetime(value) {} }
        return try await operation(value)
    }

    /// Calls `operation` with a generated value and keeps its runtime resources alive.
    ///
    /// The operation's precise error type is preserved.
    ///
    /// Use this method when passing `type(of: value)` to code that invokes static
    /// or initializer requirements. A metatype extracted from the value must not
    /// escape `operation`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withMaterializedValue(operation)
    }

    /// Asynchronously calls `operation` with a generated value and keeps its runtime resources alive.
    ///
    /// The operation's precise error type is preserved.
    ///
    /// Use this method when passing `type(of: value)` to code that invokes static
    /// or initializer requirements. A metatype extracted from the value must not
    /// escape `operation`.
    public func withValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withMaterializedValue(operation)
    }
}

extension Stub where P: Sendable {
    /// Returns the generated `Sendable` protocol existential.
    ///
    /// This compatibility overload remains functional, but use
    /// ``callAsFunction(sendability:)`` to make the unchecked concurrency
    /// boundary explicit.
    @available(
        *,
        deprecated,
        message: "Use `stub(sendability: .unchecked)` to acknowledge unchecked Sendable state."
    )
    public func callAsFunction() -> P {
        materializeUnchecked()
    }

    /// Returns the generated `Sendable` protocol existential after the caller
    /// explicitly accepts responsibility for its unchecked stored state.
    public func callAsFunction(sendability: StubSendability) -> P {
        switch sendability {
            case .unchecked:
                materializeUnchecked()
        }
    }

    /// Calls `operation` with a generated `Sendable` value.
    ///
    /// This compatibility overload remains functional, but use
    /// `withValue(sendability:_:)` to make the unchecked concurrency boundary
    /// explicit.
    @available(
        *,
        deprecated,
        message: "Use `withValue(sendability: .unchecked)` to acknowledge unchecked Sendable state."
    )
    public func withValue<Result, Failure: Error>(
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try withMaterializedValue(operation)
    }

    /// Calls `operation` with a generated `Sendable` value after the caller
    /// explicitly accepts responsibility for its unchecked stored state.
    public func withValue<Result, Failure: Error>(
        sendability: StubSendability,
        _ operation: (P) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        switch sendability {
            case .unchecked:
                try withMaterializedValue(operation)
        }
    }

    /// Asynchronously calls `operation` with a generated `Sendable` value.
    ///
    /// This compatibility overload remains functional, but use
    /// `withValue(sendability:_:)` to make the unchecked concurrency boundary
    /// explicit.
    @available(
        *,
        deprecated,
        message: "Use `withValue(sendability: .unchecked)` to acknowledge unchecked Sendable state."
    )
    public func withValue<Result, Failure: Error>(
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        try await withMaterializedValue(operation)
    }

    /// Asynchronously calls `operation` with a generated `Sendable` value
    /// after the caller explicitly accepts responsibility for its unchecked
    /// stored state.
    public func withValue<Result, Failure: Error>(
        sendability: StubSendability,
        _ operation: (P) async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        switch sendability {
            case .unchecked:
                try await withMaterializedValue(operation)
        }
    }
}

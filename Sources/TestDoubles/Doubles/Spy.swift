/// A runtime-generated test double that records calls and forwards unmatched
/// instance requirements to a real implementation.
///
/// Configure only the interactions a test needs to replace. Every other
/// supported call uses the forwarding target's behavior and is still available
/// to the inherited verification API.
///
/// ```swift
/// let spy: Spy<any UserService> = makeSpy(forwardingTo: liveService)
/// spy.when { $0.displayName(for: "guest") }.thenReturn("Test Guest")
///
/// let service: any UserService = spy()
/// _ = service.displayName(for: "guest") // overridden
/// _ = service.displayName(for: "admin") // forwarded
/// ```
public final class Spy<P>: Stub<P> {
    /// Creates a spy that forwards unmatched instance requirements to `target`.
    ///
    /// The target's own witness tables provide signature discovery, so this
    /// initializer does not need a separately linked conformer or explicit
    /// ``Stub/Requirement`` values.
    public convenience init(forwardingTo target: P) throws(StubError) {
        try self.init(forwardingTo: target, getterEffectInput: .automatic)
    }

    /// Creates a single-root protocol spy using the target's witness tables plus
    /// one throwing-effect hint for each getter.
    ///
    /// Supply effects in base-first, depth-first getter declaration order. Every
    /// getter must have a hint because Swift runtime metadata does not distinguish
    /// a synchronous nonthrowing getter from a synchronous throwing getter.
    public convenience init(
        forwardingTo target: P,
        getterEffects firstEffect: Stub<P>.GetterEffect,
        _ additionalEffects: Stub<P>.GetterEffect...
    ) throws(StubError) {
        try self.init(
            forwardingTo: target,
            getterEffectInput: .ordered([firstEffect] + additionalEffects)
        )
    }

    /// Creates a spy using getter-effect hints grouped by their declaring protocols.
    ///
    /// Use this initializer for inheritance graphs and protocol compositions.
    /// Group order does not matter. Supply one group for every protocol that
    /// directly declares a getter.
    public convenience init(
        forwardingTo target: P,
        getterEffectsByProtocol firstGroup: Stub<P>.ProtocolGetterEffects,
        _ additionalGroups: Stub<P>.ProtocolGetterEffects...
    ) throws(StubError) {
        try self.init(
            forwardingTo: target,
            getterEffectInput: .grouped([firstGroup] + additionalGroups)
        )
    }

    fileprivate init(
        forwardingTo target: P,
        getterEffectInput: SpyGetterEffectInput<P>
    ) throws(StubError) {
        let prepared = try withStubConstructionError(for: P.self) {
            try Stub<P>.prepareSpy(
                forwardingTo: target,
                getterEffects: getterEffectInput
            )
        }
        super.init(prepared: prepared)
    }
}

/// Returns a forwarding spy for `protocolType` that records calls to `target`.
///
/// The protocol metatype defaults to the contextual type, so prefer stating
/// the existential in the result annotation:
///
/// ```swift
/// let spy: Spy<any UserService> = makeSpy(forwardingTo: liveService)
/// ```
///
/// Without an annotation or an explicit metatype, `P` is inferred from the
/// target's concrete implementation type, which fails fast with a
/// protocol-existential diagnostic. Construction also terminates the process
/// when the protocol cannot be forwarded safely. Use the throwing
/// ``Spy/init(forwardingTo:)`` initializer when construction failure must be
/// handled by the caller.
///
/// - Parameters:
///   - protocolType: The protocol metatype implemented by the returned spy.
///     Defaults to the contextual type.
///   - target: The real protocol implementation that receives unmatched calls.
/// - Returns: A forwarding spy that supports stubbing and verification.
public func makeSpy<P>(
    _ protocolType: P.Type = P.self,
    forwardingTo target: P
) -> Spy<P> {
    constructSpyOrFail(for: protocolType) { () throws(StubError) -> Spy<P> in
        try Spy<P>(forwardingTo: target)
    }
}

/// Returns a forwarding spy using one throwing-effect hint for each getter.
///
/// The target still supplies every discoverable signature component. Effects
/// only provide the getter throwing information omitted by runtime metadata.
public func makeSpy<P>(
    _ protocolType: P.Type = P.self,
    forwardingTo target: P,
    getterEffects firstEffect: Stub<P>.GetterEffect,
    _ additionalEffects: Stub<P>.GetterEffect...
) -> Spy<P> {
    let effects = [firstEffect] + additionalEffects
    return constructSpyOrFail(for: protocolType) { () throws(StubError) -> Spy<P> in
        try Spy<P>(
            forwardingTo: target,
            getterEffectInput: .ordered(effects)
        )
    }
}

/// Returns a forwarding spy using getter-effect hints grouped by their declaring protocols.
public func makeSpy<P>(
    _ protocolType: P.Type = P.self,
    forwardingTo target: P,
    getterEffectsByProtocol firstGroup: Stub<P>.ProtocolGetterEffects,
    _ additionalGroups: Stub<P>.ProtocolGetterEffects...
) -> Spy<P> {
    let groups = [firstGroup] + additionalGroups
    return constructSpyOrFail(for: protocolType) { () throws(StubError) -> Spy<P> in
        try Spy<P>(
            forwardingTo: target,
            getterEffectInput: .grouped(groups)
        )
    }
}

private func constructSpyOrFail<P>(
    for protocolType: P.Type,
    _ operation: () throws(StubError) -> Spy<P>
) -> Spy<P> {
    constructTestDoubleOrFail(.spy, for: protocolType, operation)
}

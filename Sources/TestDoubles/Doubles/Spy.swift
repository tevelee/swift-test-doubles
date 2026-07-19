/// A runtime-generated test double that records calls and forwards unmatched
/// instance requirements to a real implementation.
///
/// Configure only the interactions a test needs to replace. Every other
/// supported call uses the forwarding target's behavior and is still available
/// to the inherited verification API.
///
/// ```swift
/// let spy = try Spy<any UserService>(forwardingTo: liveService)
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
    public init(forwardingTo target: P) throws {
        let shape = try Stub<P>.extractProtocolShape()
        let forwardingTarget = try ForwardingTarget(
            target,
            layout: shape.layout,
            representation: shape.representation
        )
        let methods = try discoverMethods(
            witnessTables: forwardingTarget.witnessTables,
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            selfIsClassConstrained: shape.representation.isClassConstrained,
            getterEffectPolicy: .automatic
        )
        let forwarder = try ProtocolForwarder(
            target: forwardingTarget,
            methods: methods,
            layout: shape.layout
        )
        let prepared = try Stub<P>.prepareFabricated(
            layout: shape.layout,
            associatedTypeBindings: shape.associatedTypeBindings,
            representation: shape.representation,
            methods: methods,
            forwarder: forwarder
        )
        super.init(prepared: prepared)
    }
}

/// Returns a configured runtime-generated stub value.
///
/// The surrounding assignment, argument, or return context must determine the
/// protocol existential type. Use an explicit ``Stub`` when configuration must
/// be followed by verification.
///
/// ```swift
/// let service: any CurrencyService = makeStub {
///     $0.when { $0.currency }.then { "EUR" }
/// }
/// ```
///
/// Construction terminates the process with a diagnostic if the protocol
/// layout or requirement signatures cannot be fabricated safely.
///
/// - Parameter configure: An operation that configures the generated stub.
/// - Returns: The configured protocol value.
public func makeStub<P>(_ configure: (Stub<P>) -> Void) -> P {
    let stub: Stub<P> = constructStubOrFail()
    configure(stub)
    return stub()
}

/// Returns a configured `Sendable` protocol value.
///
/// This compatibility overload remains functional, but use
/// ``makeStub(sendability:_:)`` to make the unchecked concurrency boundary
/// explicit.
@available(
    *,
    deprecated,
    message: "Use `makeStub(sendability: .unchecked)` to acknowledge unchecked Sendable state."
)
public func makeStub<P: Sendable>(_ configure: (Stub<P>) -> Void) -> P {
    let stub: Stub<P> = constructStubOrFail()
    configure(stub)
    return stub(sendability: .unchecked)
}

/// Returns a configured `Sendable` protocol value after the caller explicitly
/// accepts responsibility for its unchecked stored state.
public func makeStub<P: Sendable>(
    sendability: StubSendability,
    _ configure: (Stub<P>) -> Void
) -> P {
    let stub: Stub<P> = constructStubOrFail()
    configure(stub)
    return stub(sendability: sendability)
}

/// Asynchronously returns a configured runtime-generated stub value.
///
/// The surrounding assignment, argument, or return context must determine the
/// protocol existential type. Use this overload when configuration records an
/// async requirement.
///
/// Construction terminates the process with a diagnostic if the protocol
/// layout or requirement signatures cannot be fabricated safely.
///
/// - Parameters:
///   - configure: An asynchronous operation that configures the generated stub.
///   - isolation: The actor on which configuration runs.
/// - Returns: The configured protocol value.
public func makeStub<P>(
    _ configure: (Stub<P>) async -> Void,
    isolation: isolated (any Actor)? = #isolation
) async -> P {
    let stub: Stub<P> = constructStubOrFail()
    await configure(stub)
    return stub()
}

/// Asynchronously returns a configured `Sendable` protocol value.
///
/// This compatibility overload remains functional, but use
/// `makeStub(sendability:_:isolation:)` to make the unchecked concurrency
/// boundary explicit.
@available(
    *,
    deprecated,
    message: "Use `makeStub(sendability: .unchecked)` to acknowledge unchecked Sendable state."
)
public func makeStub<P: Sendable>(
    _ configure: (Stub<P>) async -> Void,
    isolation: isolated (any Actor)? = #isolation
) async -> P {
    let stub: Stub<P> = constructStubOrFail()
    await configure(stub)
    return stub(sendability: .unchecked)
}

/// Asynchronously returns a configured `Sendable` protocol value after the
/// caller explicitly accepts responsibility for its unchecked stored state.
public func makeStub<P: Sendable>(
    sendability: StubSendability,
    _ configure: (Stub<P>) async -> Void,
    isolation: isolated (any Actor)? = #isolation
) async -> P {
    let stub: Stub<P> = constructStubOrFail()
    await configure(stub)
    return stub(sendability: sendability)
}

private func constructStubOrFail<P>() -> Stub<P> {
    do {
        return try Stub<P>()
    } catch {
        fatalError(
            "[TestDoubles] Could not construct a stub for '\(String(reflecting: P.self))': \(error)"
        )
    }
}

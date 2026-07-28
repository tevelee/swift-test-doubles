/// Reusable synchronous configuration for a test double.
///
/// Prefer the ``StubScenario`` and ``ManualStubScenario`` aliases at call
/// sites. A scenario packages ordinary `when` registrations and can be
/// appended to another scenario in registration order.
public struct TestDoubleScenario<Subject> {
    private let configure: (Subject) -> Void

    /// Creates a reusable synchronous double configuration.
    public init(_ configure: @escaping (Subject) -> Void) {
        self.configure = configure
    }

    /// Applies this scenario's registrations to `subject`.
    public func apply(to subject: Subject) {
        configure(subject)
    }

    /// Returns a scenario that applies this scenario, then `next`.
    ///
    /// Registration order matters because stubs use first-match-wins.
    public func appending(_ next: Self) -> Self {
        Self { subject in
            apply(to: subject)
            next.apply(to: subject)
        }
    }
}

/// Reusable synchronous configuration for a runtime-generated ``Stub``.
public typealias StubScenario<P> = TestDoubleScenario<Stub<P>>

/// Reusable synchronous configuration for a ``ManualStub``.
public typealias ManualStubScenario<T: StubConformer> = TestDoubleScenario<ManualStub<T>>

/// Reusable asynchronous configuration for a test double.
///
/// Prefer the ``AsyncStubScenario`` and ``AsyncManualStubScenario`` aliases at
/// call sites. Use this type when the configuration records an async
/// requirement.
public struct AsyncTestDoubleScenario<Subject> {
    private let configure: (Subject) async -> Void

    /// Creates a reusable asynchronous double configuration.
    public init(_ configure: @escaping (Subject) async -> Void) {
        self.configure = configure
    }

    /// Applies this scenario's registrations to `subject`.
    public func apply(to subject: Subject) async {
        await configure(subject)
    }

    /// Returns a scenario that applies this scenario, then `next`.
    ///
    /// Registration order matters because stubs use first-match-wins.
    public func appending(_ next: Self) -> Self {
        Self { subject in
            await apply(to: subject)
            await next.apply(to: subject)
        }
    }
}

/// Reusable asynchronous configuration for a runtime-generated ``Stub``.
public typealias AsyncStubScenario<P> = AsyncTestDoubleScenario<Stub<P>>

/// Reusable asynchronous configuration for a ``ManualStub``.
public typealias AsyncManualStubScenario<T: StubConformer> = AsyncTestDoubleScenario<ManualStub<T>>

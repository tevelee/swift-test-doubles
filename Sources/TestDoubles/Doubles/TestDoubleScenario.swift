enum TestDoubleScenarioContext {
    @TaskLocal static var name: String?
}

/// Reusable synchronous configuration for a test double.
///
/// Prefer the ``StubScenario`` and ``ManualStubScenario`` aliases at call
/// sites. A scenario packages ordinary `when` registrations and can be
/// appended to another scenario in registration order.
public struct TestDoubleScenario<Subject> {
    private let configure: (Subject) -> Void
    /// A name included in diagnostics when this scenario conflicts with
    /// another scenario or a directly registered behavior.
    public let name: String?

    /// Creates a reusable synchronous double configuration.
    public init(_ configure: @escaping (Subject) -> Void) {
        name = nil
        self.configure = configure
    }

    /// Creates a named scenario. Names make first-match-wins conflicts
    /// actionable when scenarios are composed.
    public init(named name: String, _ configure: @escaping (Subject) -> Void) {
        self.name = name
        self.configure = configure
    }

    /// Applies this scenario's registrations to `subject`.
    public func apply(to subject: Subject) {
        TestDoubleScenarioContext.$name.withValue(name) {
            configure(subject)
        }
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

/// Reusable synchronous configuration for a ``CompiledStub``.
public typealias ManualStubScenario<T> = TestDoubleScenario<CompiledStub<T>>

/// A reusable synchronous scenario that receives test-specific input when it
/// is applied.
///
/// This keeps a scenario's shared setup in one place without forcing callers
/// to build an ad-hoc closure for every fixture value.
public struct ParameterizedTestDoubleScenario<Subject, Parameter> {
    private let configure: (Subject, Parameter) -> Void
    /// A name included in scenario-conflict diagnostics.
    public let name: String?

    /// Creates an unnamed parameterized scenario.
    public init(_ configure: @escaping (Subject, Parameter) -> Void) {
        name = nil
        self.configure = configure
    }

    /// Creates a named parameterized scenario.
    public init(named name: String, _ configure: @escaping (Subject, Parameter) -> Void) {
        self.name = name
        self.configure = configure
    }

    /// Applies the scenario with `parameter`.
    public func apply(_ parameter: Parameter, to subject: Subject) {
        TestDoubleScenarioContext.$name.withValue(name) {
            configure(subject, parameter)
        }
    }

    /// Binds one parameter and returns an ordinary reusable scenario.
    public func scenario(for parameter: Parameter) -> TestDoubleScenario<Subject> {
        TestDoubleScenario<Subject>(named: name ?? "parameterized scenario") { subject in
            apply(parameter, to: subject)
        }
    }
}

/// A parameterized scenario for a runtime-generated ``Stub``.
public typealias ParameterizedStubScenario<P, Parameter> =
    ParameterizedTestDoubleScenario<Stub<P>, Parameter>

/// A parameterized scenario for a ``CompiledStub``.
public typealias ParameterizedManualStubScenario<T, Parameter> =
    ParameterizedTestDoubleScenario<CompiledStub<T>, Parameter>

/// Reusable asynchronous configuration for a test double.
///
/// Prefer the ``AsyncStubScenario`` and ``AsyncManualStubScenario`` aliases at
/// call sites. Use this type when the configuration records an async
/// requirement.
public struct AsyncTestDoubleScenario<Subject> {
    private let configure: (Subject) async -> Void
    /// A name included in diagnostics when this scenario conflicts with
    /// another scenario or a directly registered behavior.
    public let name: String?

    /// Creates a reusable asynchronous double configuration.
    public init(_ configure: @escaping (Subject) async -> Void) {
        name = nil
        self.configure = configure
    }

    /// Creates a named asynchronous scenario.
    public init(named name: String, _ configure: @escaping (Subject) async -> Void) {
        self.name = name
        self.configure = configure
    }

    /// Applies this scenario's registrations to `subject`.
    public func apply(to subject: Subject) async {
        await TestDoubleScenarioContext.$name.withValue(name) {
            await configure(subject)
        }
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

/// Reusable asynchronous configuration for a ``CompiledStub``.
public typealias AsyncManualStubScenario<T> = AsyncTestDoubleScenario<CompiledStub<T>>

/// A reusable asynchronous scenario that receives test-specific input when it
/// is applied.
public struct AsyncParameterizedTestDoubleScenario<Subject, Parameter> {
    private let configure: (Subject, Parameter) async -> Void
    /// A name included in scenario-conflict diagnostics.
    public let name: String?

    /// Creates an unnamed asynchronous parameterized scenario.
    public init(_ configure: @escaping (Subject, Parameter) async -> Void) {
        name = nil
        self.configure = configure
    }

    /// Creates a named asynchronous parameterized scenario.
    public init(
        named name: String,
        _ configure: @escaping (Subject, Parameter) async -> Void
    ) {
        self.name = name
        self.configure = configure
    }

    /// Applies the scenario with `parameter`.
    public func apply(_ parameter: Parameter, to subject: Subject) async {
        await TestDoubleScenarioContext.$name.withValue(name) {
            await configure(subject, parameter)
        }
    }

    /// Binds one parameter and returns an ordinary asynchronous scenario.
    public func scenario(for parameter: Parameter) -> AsyncTestDoubleScenario<Subject> {
        AsyncTestDoubleScenario<Subject>(named: name ?? "parameterized scenario") { subject in
            await apply(parameter, to: subject)
        }
    }
}

/// A parameterized asynchronous scenario for a runtime-generated ``Stub``.
public typealias AsyncParameterizedStubScenario<P, Parameter> =
    AsyncParameterizedTestDoubleScenario<Stub<P>, Parameter>

/// A parameterized asynchronous scenario for a ``CompiledStub``.
public typealias AsyncParameterizedManualStubScenario<T, Parameter> =
    AsyncParameterizedTestDoubleScenario<CompiledStub<T>, Parameter>

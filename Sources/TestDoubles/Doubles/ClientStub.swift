/// A test-double controller for a concrete dependency value whose operations
/// are stored closures.
///
/// Construct the client from the supplied ``ClientStubEndpoints`` and inject
/// the value returned by calling the stub. Every endpoint shares one recorder,
/// so configuration, verification, interaction ordering, strict scopes, and
/// reset behavior work the same way as they do for a protocol ``Stub``.
///
/// ```swift
/// struct APIClient {
///     var fetchUser: @Sendable (Int) async throws -> User
///     var track: @Sendable (Event) async -> Void
/// }
///
/// let stub = ClientStub<APIClient> { endpoints in
///     APIClient(
///         fetchUser: endpoints.asyncThrowingFunction("fetchUser"),
///         track: endpoints.asyncFunction("track")
///     )
/// }
///
/// await stub.when {
///     try await $0.fetchUser(Match.equal(42))
/// }.thenReturn(user)
///
/// let client: APIClient = stub()
/// ```
public typealias ClientStub<Client> = ManualStub<Client>

/// A test-double controller that records a closure-field client's calls and
/// forwards unmatched endpoints to a live client.
///
/// Configure selected calls with the ordinary stubbing API. Calls without a
/// matching configuration delegate to the corresponding live closure and are
/// available through forwarded interaction filters.
///
/// ```swift
/// let spy = ClientSpy<APIClient>(forwardingTo: .live) { endpoints in
///     APIClient(
///         fetchUser: endpoints.asyncThrowingFunction(
///             "fetchUser",
///             forwarding: { live, identifier in
///                 try await live.fetchUser(identifier)
///             }
///         )
///     )
/// }
/// ```
public typealias ClientSpy<Client> = ManualStub<Client>

extension ManualStub {
    /// Creates a stub for a concrete closure-field dependency value.
    ///
    /// `materialize` can be called more than once. Construct a fresh value from
    /// the supplied endpoints each time, and synchronize mutable captured state
    /// if the stub can be materialized concurrently.
    public convenience init(
        _ materialize: @escaping (ClientStubEndpoints<T>) -> T
    ) {
        self.init(materializing: { stub in
            materialize(ClientStubEndpoints(stub: stub))
        })
    }

    /// Creates a recording client that forwards unmatched calls to `live`.
    ///
    /// Use a `forwarding:` adapter for each closure that should delegate.
    /// Configured answers take precedence, including
    /// `thenForward()` answers that explicitly resume delegation.
    public convenience init(
        forwardingTo live: T,
        _ materialize: @escaping (ClientStubEndpoints<T>) -> T
    ) {
        self.init(
            materializing: { stub in
                materialize(
                    ClientStubEndpoints(
                        stub: stub,
                        forwardingTo: live
                    )
                )
            },
            allowsForwardingFallback: true
        )
    }
}

/// Reusable wiring for a closure-field dependency's live, failing, and
/// partially overridden variants.
///
/// Define the field mapping once, then choose the policy at each test or
/// application boundary:
///
/// ```swift
/// let apiClients = ClientDoublePreset<APIClient> { endpoints in
///     APIClient(
///         fetchUser: endpoints.asyncThrowingFunction(
///             "fetchUser",
///             forwarding: { live, identifier in
///                 try await live.fetchUser(identifier)
///             }
///         )
///     )
/// }
///
/// let failing = apiClients.failing()
/// let spy = apiClients.spy(forwardingTo: .live)
/// let live = apiClients.live(.live)
/// ```
public struct ClientDoublePreset<Client>: @unchecked Sendable {
    private let materialize: (ClientStubEndpoints<Client>) -> Client

    /// Creates reusable endpoint wiring for `Client`.
    public init(
        _ materialize: @escaping (ClientStubEndpoints<Client>) -> Client
    ) {
        self.materialize = materialize
    }

    /// Returns the live value unchanged for environment-style composition.
    public func live(_ client: Client) -> Client {
        client
    }

    /// Creates a fail-closed stub. Every invoked endpoint must be configured.
    public func failing() -> ClientStub<Client> {
        ClientStub<Client>(materialize)
    }

    /// Creates a fail-closed stub and configures it before returning it.
    ///
    /// Keep the returned controller when the test needs verification, history,
    /// reset, or additional behavior changes. Inject its concrete client with
    /// `callAsFunction()`.
    public func failing(
        configure: (ClientStub<Client>) -> Void
    ) -> ClientStub<Client> {
        let stub = failing()
        configure(stub)
        return stub
    }

    /// Creates a fail-closed stub and asynchronously configures it before
    /// returning it.
    public func failing(
        configure: (ClientStub<Client>) async throws -> Void
    ) async rethrows -> ClientStub<Client> {
        let stub = failing()
        try await configure(stub)
        return stub
    }

    /// Compatibility spelling emphasizing that the result is a stub.
    public func stub() -> ClientStub<Client> {
        failing()
    }

    /// Compatibility spelling for `failing(configure:)`.
    public func stub(
        configure: (ClientStub<Client>) -> Void
    ) -> ClientStub<Client> {
        failing(configure: configure)
    }

    /// Asynchronous compatibility spelling for `failing(configure:)`.
    public func stub(
        configure: (ClientStub<Client>) async throws -> Void
    ) async rethrows -> ClientStub<Client> {
        try await failing(configure: configure)
    }

    /// Creates a recording client whose unmatched calls delegate to `live`.
    public func spy(forwardingTo live: Client) -> ClientSpy<Client> {
        ClientSpy<Client>(
            forwardingTo: live,
            materialize
        )
    }

    /// Creates a forwarding spy and configures it before returning it.
    public func spy(
        forwardingTo live: Client,
        configure: (ClientSpy<Client>) -> Void
    ) -> ClientSpy<Client> {
        let spy = self.spy(forwardingTo: live)
        configure(spy)
        return spy
    }

    /// Creates a forwarding spy and asynchronously configures it before
    /// returning it.
    public func spy(
        forwardingTo live: Client,
        configure: (ClientSpy<Client>) async throws -> Void
    ) async rethrows -> ClientSpy<Client> {
        let spy = self.spy(forwardingTo: live)
        try await configure(spy)
        return spy
    }

    /// Creates a forwarding spy and applies selective overrides before use.
    ///
    /// The returned controller remains available for verification and
    /// materializes the partially overridden client via `callAsFunction()`.
    public func overriding(
        _ live: Client,
        configure: (ClientSpy<Client>) -> Void
    ) -> ClientSpy<Client> {
        spy(
            forwardingTo: live,
            configure: configure
        )
    }

    /// Asynchronously configures selected overrides before returning the spy.
    public func overriding(
        _ live: Client,
        configure: (ClientSpy<Client>) async throws -> Void
    ) async rethrows -> ClientSpy<Client> {
        try await spy(
            forwardingTo: live,
            configure: configure
        )
    }

    /// Builds a fail-closed concrete client value for direct injection.
    ///
    /// This is convenient when the test does not need to inspect the
    /// controller after use. Use `failing(configure:)` instead when
    /// verification, history, reset, or later reconfiguration is required.
    public func testValue(
        configure: (ClientStub<Client>) -> Void = { _ in }
    ) -> Client {
        failing(configure: configure)()
    }

    /// Builds a fail-closed concrete client value after asynchronous
    /// configuration.
    public func testValue(
        configure: (ClientStub<Client>) async throws -> Void
    ) async rethrows -> Client {
        try await failing(configure: configure)()
    }

    /// Builds a selectively overridden concrete client value for direct
    /// injection. Unmatched calls delegate to `live`.
    ///
    /// Use `spy(forwardingTo:configure:)` when the test needs to inspect the
    /// controller after use.
    public func testValue(
        overriding live: Client,
        configure: (ClientSpy<Client>) -> Void
    ) -> Client {
        spy(
            forwardingTo: live,
            configure: configure
        )()
    }

    /// Builds a selectively overridden concrete client value after
    /// asynchronous configuration.
    public func testValue(
        overriding live: Client,
        configure: (ClientSpy<Client>) async throws -> Void
    ) async rethrows -> Client {
        try await spy(
            forwardingTo: live,
            configure: configure
        )()
    }
}

/// Manufactures typed closure endpoints backed by one ``ClientStub`` recorder.
///
/// Choose the factory matching the closure field's effects. Argument and result
/// types are inferred from the client initializer receiving the returned
/// closure. Endpoint names appear in diagnostics and must distinguish fields
/// that otherwise have the same function signature.
public struct ClientStubEndpoints<Client>: @unchecked Sendable {
    private enum ForwardingTarget {
        case none
        case client(Client)
    }

    private let stub: ManualStub<Client>
    private let forwardingTarget: ForwardingTarget

    init(stub: ManualStub<Client>) {
        self.stub = stub
        forwardingTarget = .none
    }

    init(
        stub: ManualStub<Client>,
        forwardingTo client: Client
    ) {
        self.stub = stub
        forwardingTarget = .client(client)
    }

    private func requiredForwardingClient() -> Client {
        guard case .client(let client) = forwardingTarget else {
            preconditionFailure(
                "[TestDoubles] A client forwarding endpoint lost its live target."
            )
        }
        return client
    }

    /// Creates a synchronous nonthrowing endpoint.
    public func function<each Argument, Result>(
        _ name: String
    ) -> @Sendable (repeat each Argument) -> Result {
        { (argument: repeat each Argument) in
            self.stub.call(
                repeat each argument,
                function: name
            )
        }
    }

    /// Creates a synchronous nonthrowing endpoint with a direct live fallback.
    public func function<each Argument, Result>(
        _ name: String,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) -> Result
    ) -> @Sendable (repeat each Argument) -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: false,
                isThrowing: false
            )
            return self.stub.dispatchValue(
                method: method,
                args: packed.values,
                forwardingTo: {
                    fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates a synchronous nonthrowing endpoint whose fallback receives the
    /// live client supplied to ``ClientSpy``.
    public func function<each Argument, Result>(
        _ name: String,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) -> Result
    ) -> @Sendable (repeat each Argument) -> Result {
        return switch forwardingTarget {
            case .none:
                function(name)
            case .client:
                function(
                    name,
                    forwardingTo: { (argument: repeat each Argument) in
                        fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }

    /// Creates a synchronous endpoint with untyped throwing behavior.
    public func throwingFunction<each Argument, Result>(
        _ name: String
    ) -> @Sendable (repeat each Argument) throws -> Result {
        { (argument: repeat each Argument) in
            try self.stub.throwingCall(
                repeat each argument,
                function: name
            )
        }
    }

    /// Creates a synchronous throwing endpoint with a direct live fallback.
    public func throwingFunction<each Argument, Result>(
        _ name: String,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) throws -> Result
    ) -> @Sendable (repeat each Argument) throws -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: false,
                isThrowing: true
            )
            return try self.stub.dispatchThrowingValue(
                method: method,
                args: packed.values,
                forwardingTo: {
                    try fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates a synchronous throwing endpoint whose fallback receives the
    /// selected live client.
    public func throwingFunction<each Argument, Result>(
        _ name: String,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) throws -> Result
    ) -> @Sendable (repeat each Argument) throws -> Result {
        return switch forwardingTarget {
            case .none:
                throwingFunction(name)
            case .client:
                throwingFunction(
                    name,
                    forwardingTo: { (argument: repeat each Argument) in
                        try fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }

    /// Creates a synchronous endpoint with a typed error channel.
    public func throwingFunction<each Argument, Result, Failure: Error>(
        _ name: String,
        throwing failureType: Failure.Type
    ) -> @Sendable (repeat each Argument) throws(Failure) -> Result {
        { (argument: repeat each Argument) in
            try self.stub.throwingCall(
                repeat each argument,
                throwing: failureType,
                function: name
            )
        }
    }

    /// Creates a synchronous typed-throws endpoint with a direct live fallback.
    public func throwingFunction<each Argument, Result, Failure: Error>(
        _ name: String,
        throwing failureType: Failure.Type,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) throws(Failure) -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: false,
                isThrowing: true
            )
            return try self.stub.dispatchThrowingValue(
                method: method,
                args: packed.values,
                throwing: failureType,
                forwardingTo: { () throws(Failure) -> Result in
                    try fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates a synchronous typed-throws endpoint whose fallback receives the
    /// selected live client.
    public func throwingFunction<each Argument, Result, Failure: Error>(
        _ name: String,
        throwing failureType: Failure.Type,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) throws(Failure) -> Result {
        return switch forwardingTarget {
            case .none:
                throwingFunction(name, throwing: failureType)
            case .client:
                throwingFunction(
                    name,
                    throwing: failureType,
                    forwardingTo: {
                        (
                            argument: repeat each Argument
                        ) throws(Failure) -> Result in
                        try fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }

    /// Creates an asynchronous nonthrowing endpoint.
    public func asyncFunction<each Argument, Result>(
        _ name: String
    ) -> @Sendable (repeat each Argument) async -> Result {
        { (argument: repeat each Argument) in
            await self.stub.call(
                repeat each argument,
                function: name
            )
        }
    }

    /// Creates an asynchronous nonthrowing endpoint with a direct live fallback.
    public func asyncFunction<each Argument, Result>(
        _ name: String,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) async -> Result
    ) -> @Sendable (repeat each Argument) async -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: true,
                isThrowing: false
            )
            return await self.stub.dispatchAsyncValue(
                method: method,
                args: packed.values,
                forwardingTo: {
                    await fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates an asynchronous nonthrowing endpoint whose fallback receives
    /// the selected live client.
    public func asyncFunction<each Argument, Result>(
        _ name: String,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) async -> Result
    ) -> @Sendable (repeat each Argument) async -> Result {
        return switch forwardingTarget {
            case .none:
                asyncFunction(name)
            case .client:
                asyncFunction(
                    name,
                    forwardingTo: { (argument: repeat each Argument) in
                        await fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }

    /// Creates an asynchronous endpoint with untyped throwing behavior.
    public func asyncThrowingFunction<each Argument, Result>(
        _ name: String
    ) -> @Sendable (repeat each Argument) async throws -> Result {
        { (argument: repeat each Argument) in
            try await self.stub.throwingCall(
                repeat each argument,
                function: name
            )
        }
    }

    /// Creates an asynchronous throwing endpoint with a direct live fallback.
    public func asyncThrowingFunction<each Argument, Result>(
        _ name: String,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) async throws -> Result
    ) -> @Sendable (repeat each Argument) async throws -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: true,
                isThrowing: true
            )
            return try await self.stub.dispatchAsyncThrowingValue(
                method: method,
                args: packed.values,
                forwardingTo: {
                    try await fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates an asynchronous throwing endpoint whose fallback receives the
    /// selected live client.
    public func asyncThrowingFunction<each Argument, Result>(
        _ name: String,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) async throws -> Result
    ) -> @Sendable (repeat each Argument) async throws -> Result {
        return switch forwardingTarget {
            case .none:
                asyncThrowingFunction(name)
            case .client:
                asyncThrowingFunction(
                    name,
                    forwardingTo: { (argument: repeat each Argument) in
                        try await fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }

    /// Creates an asynchronous endpoint with a typed error channel.
    public func asyncThrowingFunction<
        each Argument,
        Result,
        Failure: Error
    >(
        _ name: String,
        throwing failureType: Failure.Type
    ) -> @Sendable (repeat each Argument) async throws(Failure) -> Result {
        { (argument: repeat each Argument) in
            try await self.stub.throwingCall(
                repeat each argument,
                throwing: failureType,
                function: name
            )
        }
    }

    /// Creates an asynchronous typed-throws endpoint with a direct live
    /// fallback.
    public func asyncThrowingFunction<
        each Argument,
        Result,
        Failure: Error
    >(
        _ name: String,
        throwing failureType: Failure.Type,
        forwardingTo fallback: @escaping @Sendable (repeat each Argument) async throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) async throws(Failure) -> Result {
        { (argument: repeat each Argument) in
            let packed = manualPackedArguments(repeat each argument)
            let method = self.stub.internMethod(
                route: packed.route(for: name),
                returnType: Result.self,
                isAsync: true,
                isThrowing: true
            )
            return try await self.stub.dispatchAsyncThrowingValue(
                method: method,
                args: packed.values,
                throwing: failureType,
                forwardingTo: { () async throws(Failure) -> Result in
                    try await fallback(repeat each argument)
                }
            )
        }
    }

    /// Creates an asynchronous typed-throws endpoint whose fallback receives
    /// the selected live client.
    public func asyncThrowingFunction<
        each Argument,
        Result,
        Failure: Error
    >(
        _ name: String,
        throwing failureType: Failure.Type,
        forwarding fallback:
            @escaping @Sendable (
                Client,
                repeat each Argument
            ) async throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) async throws(Failure) -> Result {
        return switch forwardingTarget {
            case .none:
                asyncThrowingFunction(name, throwing: failureType)
            case .client:
                asyncThrowingFunction(
                    name,
                    throwing: failureType,
                    forwardingTo: {
                        (
                            argument: repeat each Argument
                        ) async throws(Failure) -> Result in
                        try await fallback(
                            self.requiredForwardingClient(),
                            repeat each argument
                        )
                    }
                )
        }
    }
}

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
}

/// Manufactures typed closure endpoints backed by one ``ClientStub`` recorder.
///
/// Choose the factory matching the closure field's effects. Argument and result
/// types are inferred from the client initializer receiving the returned
/// closure. Endpoint names appear in diagnostics and must distinguish fields
/// that otherwise have the same function signature.
public struct ClientStubEndpoints<Client>: Sendable {
    private let stub: ManualStub<Client>

    init(stub: ManualStub<Client>) {
        self.stub = stub
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
}

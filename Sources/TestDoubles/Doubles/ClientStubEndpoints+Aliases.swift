extension ClientStubEndpoints {
    /// Creates a synchronous endpoint from a named closure type.
    ///
    /// This overload lets generated and hand-written presets support closure
    /// type aliases whose declarations are outside the client struct.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: (@Sendable (repeat each Argument) -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) -> Result
    ) -> @Sendable (repeat each Argument) -> Result {
        function(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) -> Result in
                forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a synchronous throwing endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: (@Sendable (repeat each Argument) throws -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) throws -> Result
    ) -> @Sendable (repeat each Argument) throws -> Result {
        throwingFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) throws -> Result in
                try forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a synchronous typed-throws endpoint from a named closure type.
    public func endpoint<each Argument, Result, Failure: Error>(
        _ name: String,
        as _: (
            @Sendable (repeat each Argument) throws(Failure) -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) throws(Failure) -> Result {
        throwingFunction(
            name,
            throwing: Failure.self,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) throws(Failure) -> Result in
                try forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates an asynchronous endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: (@Sendable (repeat each Argument) async -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) async -> Result
    ) -> @Sendable (repeat each Argument) async -> Result {
        asyncFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async -> Result in
                await forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates an asynchronous throwing endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: (
            @Sendable (repeat each Argument) async throws -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) async throws -> Result
    ) -> @Sendable (repeat each Argument) async throws -> Result {
        asyncThrowingFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async throws -> Result in
                try await forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates an asynchronous typed-throws endpoint from a named closure type.
    public func endpoint<each Argument, Result, Failure: Error>(
        _ name: String,
        as _: (
            @Sendable (repeat each Argument) async throws(Failure) -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            @Sendable (repeat each Argument) async throws(Failure) -> Result
    ) -> @Sendable (repeat each Argument) async throws(Failure) -> Result {
        asyncThrowingFunction(
            name,
            throwing: Failure.self,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async throws(Failure) -> Result in
                try await forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` synchronous endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: ((repeat each Argument) -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) -> Result
    ) -> (repeat each Argument) -> Result {
        return function(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) -> Result in
                forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` throwing endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: ((repeat each Argument) throws -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) throws -> Result
    ) -> (repeat each Argument) throws -> Result {
        return throwingFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) throws -> Result in
                try forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` typed-throws endpoint from a named closure type.
    public func endpoint<each Argument, Result, Failure: Error>(
        _ name: String,
        as _: (
            (repeat each Argument) throws(Failure) -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) throws(Failure) -> Result
    ) -> (repeat each Argument) throws(Failure) -> Result {
        return throwingFunction(
            name,
            throwing: Failure.self,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) throws(Failure) -> Result in
                try forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` asynchronous endpoint from a named closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: ((repeat each Argument) async -> Result).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) async -> Result
    ) -> (repeat each Argument) async -> Result {
        return asyncFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async -> Result in
                await forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` asynchronous throwing endpoint from a named
    /// closure type.
    public func endpoint<each Argument, Result>(
        _ name: String,
        as _: (
            (repeat each Argument) async throws -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) async throws -> Result
    ) -> (repeat each Argument) async throws -> Result {
        return asyncThrowingFunction(
            name,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async throws -> Result in
                try await forwarding(client)(repeat each argument)
            }
        )
    }

    /// Creates a non-`Sendable` asynchronous typed-throws endpoint from a named
    /// closure type.
    public func endpoint<each Argument, Result, Failure: Error>(
        _ name: String,
        as _: (
            (repeat each Argument) async throws(Failure) -> Result
        ).Type,
        forwarding:
            @escaping @Sendable (Client) ->
            (repeat each Argument) async throws(Failure) -> Result
    ) -> (repeat each Argument) async throws(Failure) -> Result {
        return asyncThrowingFunction(
            name,
            throwing: Failure.self,
            forwarding: {
                (
                    client: Client,
                    argument: repeat each Argument
                ) async throws(Failure) -> Result in
                try await forwarding(client)(repeat each argument)
            }
        )
    }
}

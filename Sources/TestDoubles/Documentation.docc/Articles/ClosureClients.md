# Closure-Based Dependencies

Stub concrete dependency clients whose operations are stored closures.

## Overview

Protocols are not required to use TestDoubles' recording and behavior engine.
``ClientStub`` builds an ordinary concrete value from typed closure endpoints,
which fits dependency-client styles where a struct contains operations and
production, test, and failing values supply different implementations.

```swift
struct APIClient: Sendable {
    var fetchUser: @Sendable (Int) async throws -> User
    var track: @Sendable (Event) -> Void
}

let stub = ClientStub<APIClient> { endpoints in
    APIClient(
        fetchUser: endpoints.asyncThrowingFunction("fetchUser"),
        track: endpoints.function("track")
    )
}

await stub.when {
    try await $0.fetchUser(Match.equal(42))
}.thenReturn(user)
stub.when {
    $0.track(Match.any())
}.thenDoNothing()

let client: APIClient = stub()
#expect(try await client.fetchUser(42) == user)

await stub.verify {
    try await $0.fetchUser(Match.equal(42))
}
```

Calling the stub materializes the dependency value. Every materialized value
and every endpoint uses the same recorder, so behavior registrations,
verification, exact ordering, strict scopes, history, and reset work across the
whole client. An endpoint without a matching behavior fails with the same
diagnostic as an unconfigured protocol or manual stub requirement.

This path does not inspect protocol metadata, fabricate a witness table, or use
the runtime trampoline. It is available wherever ``ManualStub`` is available,
including targets that disable the `RuntimeStubs` package trait.

### Choose endpoint effects

``ClientStubEndpoints`` provides one factory for each effect combination:

- `function(_:)` for synchronous nonthrowing operations
- `throwingFunction(_:)` for synchronous throwing operations
- `asyncFunction(_:)` for asynchronous nonthrowing operations
- `asyncThrowingFunction(_:)` for asynchronous throwing operations

Typed-throws overloads accept the failure metatype:

```swift
enum APIError: Error {
    case unavailable
}

struct StatusClient {
    var status: @Sendable () async throws(APIError) -> String
}

let stub = ClientStub<StatusClient> { endpoints in
    StatusClient(
        status: endpoints.asyncThrowingFunction(
            "status",
            throwing: APIError.self
        )
    )
}
```

The client initializer supplies the contextual argument and result types.
Endpoint factories use parameter packs, so nullary and multi-argument
operations use the same API and are not capped at a fixed arity:

```swift
struct SearchClient {
    var search:
        @Sendable (
            String,
            Int,
            Int,
            String,
            Bool,
            Double
        ) async throws -> [SearchResult]
}

let stub = ClientStub<SearchClient> { endpoints in
    SearchClient(
        search: endpoints.asyncThrowingFunction("search")
    )
}
```

Give every endpoint a stable, human-readable name. The name and the static
argument types form its route identity, so overloads with different argument
types remain independent. Use distinct names for separate fields with the same
signature so their behaviors and histories do not overlap.

### Double one standalone function

Use ``ClosureDouble`` and its effectful variants when a test needs a controller
for one function rather than a whole dependency value. Their primary
`function` property models unary functions. For multiple arguments, declare
`Input` as a tuple and call `expandedFunction()`:

```swift
let format = ClosureDouble<(Int, String, Bool), String>()

let enabled = format.whenArguments {
    (count: Int, _: String, enabled: Bool) in
    count > 0 && enabled
}
enabled.thenArguments {
    (count: Int, unit: String, _: Bool) in
    "\(count) \(unit)"
}

let function: (Int, String, Bool) -> String =
    format.expandedFunction()

#expect(function(2, "items", true) == "2 items")
enabled.verify()
```

The same adapters are available on ``ThrowingClosureDouble``,
``AsyncClosureDouble``, and ``AsyncThrowingClosureDouble``:

- `expandedFunction()` produces a nullary or arbitrary-arity function with the
  double's effects.
- `invoke(_:)` invokes it with separate arguments without first storing a
  function value.
- `whenArguments(_:)` matches separate typed arguments.
- `thenArguments` computes a result from separate typed arguments.
- `thenForEachCallArguments` adds a one-based behavior call count before those
  arguments.

Fixed behaviors such as `thenReturn`, `thenThrow`, delayed results,
suspension, and cancellation remain available through `whenAny()` and
`whenArguments(_:)`. Interaction argument inspection returns the tuple used as
the double's `Input`.

### Reuse client configurations

Because ``ClientStub`` is a ``ManualStub`` specialization, synchronous and
asynchronous manual-stub scenarios can configure it:

```swift
let authenticated = AsyncManualStubScenario<APIClient> { stub in
    await stub.when {
        try await $0.fetchUser(Match.any())
    }.thenReturn(user)
}
```

Prefer a small factory for the endpoint wiring and scenarios for
test-specific behavior. That keeps the dependency's structural definition
separate from the cases each test intends to override.

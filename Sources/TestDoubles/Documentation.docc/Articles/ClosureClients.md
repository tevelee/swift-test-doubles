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

For a closure type alias, `endpoint(_:as:forwarding:)` lets the compiler
decompose the named type while preserving its arity, concurrency annotation,
and effect signature:

```swift
typealias Fetch = @Sendable (Int, String) async throws -> User

let preset = ClientDoublePreset<APIClient> { endpoints in
    APIClient(
        fetchUser: endpoints.endpoint(
            "fetchUser",
            as: Fetch.self,
            forwarding: { $0.fetchUser }
        )
    )
}
```

This bridge supports synchronous, throwing, typed-throwing, asynchronous, and
asynchronous-throwing aliases. Both `Sendable` and legacy non-`Sendable`
function aliases are accepted.

### Forward and selectively override a live client

``ClientSpy`` delegates unmatched calls while retaining the same configuration,
verification, ordering, and history API as a stub. A forwarding adapter receives
the live client followed by the endpoint's ordinary arguments:

```swift
let apiClients = ClientDoublePreset<APIClient> { endpoints in
    APIClient(
        fetchUser: endpoints.asyncThrowingFunction(
            "fetchUser",
            forwarding: { live, identifier in
                try await live.fetchUser(identifier)
            }
        ),
        track: endpoints.function(
            "track",
            forwarding: { live, event in
                live.track(event)
            }
        )
    )
}

let spy = apiClients.spy(forwardingTo: liveAPI)
await spy.when {
    try await $0.fetchUser(Match.equal(42))
}.thenReturn(testUser)

let client = spy()
#expect(try await client.fetchUser(42) == testUser) // stubbed
#expect(try await client.fetchUser(7) == liveUser)  // forwarded

spy.history.stubbed.verify()
spy.history.forwarded.verify()
```

The adapter form keeps the field mapping reusable without trying to extract a
variadic closure through a generic key path. For one-off construction, each
endpoint also has a `forwardingTo:` overload that accepts the live closure
directly.

A configured answer always wins over the fallback. End a sequence with
`thenForward()`, or attach `thenForward()` to a narrower pattern, to explicitly
punch through a broader override. Forwarded calls remain visible through
`pattern.forwarded`, `spy.history.forwarded`, timelines, streams, and order
verification.

### Reuse live, failing, and partial variants

``ClientDoublePreset`` owns structural endpoint wiring, not test behavior. Use
one preset to choose among:

- `live(_:)`, which passes a production client through unchanged
- `failing()` (or `stub()`), which requires every used endpoint to be stubbed
- `spy(forwardingTo:)`, which records and delegates unmatched calls
- `overriding(_:configure:)`, which prepares selected overrides before
  returning the spy controller

The controller factories also accept trailing configuration closures:

```swift
let stub = await apiClients.failing {
    await $0.when { try await $0.fetchUser(Match.equal(42)) }
        .thenReturn(testUser)
}

let spy = await apiClients.spy(forwardingTo: liveAPI) {
    await $0.when { try await $0.fetchUser(Match.equal(42)) }
        .thenReturn(testUser)
}
```

Keep these controllers when the test needs verification, history, resets, or
later reconfiguration, and inject `controller()` as the concrete client. For a
lightweight dependency override that only needs the client value, materialize
it in one expression:

```swift
let client = await apiClients.testValue {
    await $0.when { try await $0.fetchUser(Match.equal(42)) }
        .thenReturn(testUser)
}

let partiallyLive = await apiClients.testValue(overriding: liveAPI) {
    await $0.when { try await $0.fetchUser(Match.equal(42)) }
        .thenReturn(testUser)
}
```

`testValue()` with no configuration is a fail-closed value: invoking any
generated endpoint reports the ordinary missing-stub failure. The endpoint
closures retain their recorder even though the controller is not returned.

When the `StubbableMacros` package trait is enabled, `@StubbableClient` can
derive the preset from stored closure fields:

```swift
import TestDoubles
import TestDoublesMacros

typealias ExternalRecord<Value> = @Sendable (Value) -> Void

@StubbableClient(aliasedEndpoints: "record")
struct StatusClient<Value: Sendable> {
    typealias Status =
        @Sendable (Int) async throws -> Value

    var namespace: String
    var status: Status
    var record: ExternalRecord<Value>
    let transform: @Sendable (Value) -> Value = { $0 }

    init(liveNamespace: String) {
        namespace = liveNamespace
        status = { _ in fatalError() }
        record = { _ in }
    }
}

let preset = StatusClientDoubles<String>.preset(namespace: "tests")
let stub = preset.failing()
let spy = preset.spy(forwardingTo: liveStatus)
```

The opt-in macro generates a peer namespace named by appending `Doubles` and a
file-private wiring initializer in an extension. It therefore works whether
the client uses the synthesized memberwise initializer, declares one or more
custom initializers, or exposes a production initializer with a deliberately
different shape. The generated initializer directly initializes the stored
fields and does not replace the client's public construction API.

Inline function types and nested non-generic closure aliases are recognized
automatically. A syntax-only attached macro cannot resolve the declaration
behind an arbitrary type name, because that name may instead be an ordinary
configuration value. List global, imported, or generic closure-alias fields in
`aliasedEndpoints` to make that intent explicit. The generated code passes the
annotated alias metatype to `endpoint(_:as:forwarding:)`, allowing Swift's type
checker to preserve arbitrary arity, async, untyped throws, and typed throws
without the macro needing to locate the alias declaration.

Ordinary generic client parameters and constraints are preserved on the
generated namespace. Required non-closure stored properties become inputs to
`preset(...)`; initialized non-closure properties and initialized immutable
closure properties retain their defaults. Generic parameter packs and value
parameters, `inout` parameters, and variadic closure parameters remain outside
the generated boundary and are diagnosed when their syntax is visible.

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

For a homogeneous variadic function, use ``VariadicClosureDouble`` and
`variadicFunction()`:

```swift
let sum = VariadicClosureDouble<Int, Int>()
sum.whenAny().then { $0.reduce(0, +) }

let function: (Int...) -> Int = sum.variadicFunction()

#expect(function(1, 2, 3) == 6)
#expect(sum.invocations == [[1, 2, 3]])
```

Each variadic call is recorded as one array. Throwing, asynchronous, and
typed-throws variants are available alongside ``VariadicClosureDouble``.
``ParameterPackClosureDouble`` provides a named parameter-pack form for
heterogeneous nullary and arbitrary-arity functions. List the argument types
first and the result type last; `expandedFunction()` produces the callable
value.

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

Prefer a ``ClientDoublePreset`` for endpoint wiring and scenarios for
test-specific behavior. This keeps the dependency's structural definition
separate from the cases each test intends to override, and the same preset can
produce a failing stub or a forwarding spy.

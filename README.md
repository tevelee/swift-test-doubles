# swift-test-doubles

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Small, protocol-based test doubles for Swift—without macros, generated
conformers, or per-stub compiler invocations.

## Quick start

```swift
let stub = try Stub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("guest")
stub.when { $0.find(id: equal(42)) }.returns("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }
```

`Stub` fabricates a protocol conformance and routes witness calls through one
fixed runtime trampoline. The same API covers synchronous, throwing, async, and
async-throwing protocol requirements.

## Installation

The package is preparing its first tagged release. Until `0.1.0`, depend on
`main` when evaluating it:

```swift
dependencies: [
    .package(
        url: "https://github.com/tevelee/swift-test-doubles",
        branch: "main"
    ),
],
targets: [
    .testTarget(
        name: "MyFeatureTests",
        dependencies: [
            .product(
                name: "TestDoubles",
                package: "swift-test-doubles"
            ),
        ]
    ),
]
```

TestDoubles requires Swift 6.1 and supports macOS 13+, Mac Catalyst 16+, arm64
Simulators for iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+, and Swift 6.2 on
Ubuntu 24.04 arm64 and x86_64. See [SUPPORT.md](SUPPORT.md) for the authoritative
release boundary.

## Common patterns

The examples in this section are mirrored by public-API consumer tests in
[DocumentationExamplesTests.swift](IntegrationTests/Consumer/Tests/TestDoublesConsumerTests/DocumentationExamplesTests.swift).

### Dynamic responses and matching

Use `returns` for a fixed response and `then` when behavior depends on the
arguments. More specific registrations win over general fallbacks:

```swift
stub.when { $0.find(id: any()) }.returns("guest")
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}.then { (id: Int) in
    "member-\(id)"
}
stub.when { $0.find(id: equal(42)) }.returns("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: -1) == "guest")
#expect(repository.find(id: 7) == "member-7")
#expect(repository.find(id: 42) == "Alice")
```

Use `any()` for a wildcard, `equal(_:)` for equality, and `matching` for a
predicate. Explicit equality outranks a literal, a literal outranks a predicate,
and a predicate outranks a wildcard or capture. The first registration wins a
specificity tie. Literal arguments use a best-effort textual comparison; prefer
`equal(_:)` when equality semantics matter.

### Async success and failure

Async requirements use the same vocabulary, and handlers may genuinely
suspend:

```swift
struct LoadError: Error, Equatable {
    let url: String
}

let stub = try Stub<any AsyncDataLoader>()
await stub.when { try await $0.load(url: equal("/users/42")) }.then {
    (url: String) async throws -> String in
    await Task.yield()
    return "profile:\(url)"
}
await stub.when { try await $0.load(url: any()) }.then {
    (url: String) async throws -> String in
    await Task.yield()
    throw LoadError(url: url)
}

let loader: any AsyncDataLoader = stub()
#expect(try await loader.load(url: "/users/42") == "profile:/users/42")

let error = await #expect(throws: LoadError.self) {
    try await loader.load(url: "/missing")
}
#expect(error?.url == "/missing")
```

Suspending handlers run as part of the invoking task, preserving task-local
values, cancellation, and priority. A handler's actor isolation is honored,
including when its actor uses a custom serial executor, and an actor-isolated
caller resumes on its executor after the requirement returns.

### Capture side effects

Capture arguments when the interaction itself is the result being tested:

```swift
let stub = try Stub<any NotificationService>()
stub.when { try $0.send(to: any(), message: any()) }

let notifications: any NotificationService = stub()
try notifications.send(to: 1, message: "Welcome")
try notifications.send(to: 2, message: "Try again")

let recipients = ArgumentCaptor<Int>()
let messages = ArgumentCaptor<String>()
stub.verify(.exactly(2)) {
    try $0.send(to: recipients.capture(), message: messages.capture())
}
#expect(recipients.values == [1, 2])
#expect(messages.values == ["Welcome", "Try again"])
```

Verification defaults to at least once. Use `.exactly(_:)` or `.never` only
when the count adds meaning to the test.

### Stateful responses

A handler may model a response sequence for serial calls:

```swift
let stub = try Stub<any UserRepository>()
var responses = ["syncing", "ready"]
stub.when { $0.find(id: equal(42)) }.then { (_: Int) in
    responses.removeFirst()
}

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "syncing")
#expect(repository.find(id: 42) == "ready")
```

If calls may be concurrent, the handler is responsible for synchronizing its
captured mutable state.

## Construction

The zero-argument initializer discovers requirement signatures from a real
conformer linked into the test process:

```swift
let stub = try Stub<any UserRepository>()
```

## Explicit requirements

If no conformer is linked, describe the requirements with Swift types. Order
must match the protocol declaration, including property accessors:

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

Effects are part of an explicit requirement:

```swift
let stub = try Stub<any AsyncDataLoader>(
    .method(
        String.self,
        returning: String.self,
        isThrowing: true,
        isAsync: true
    ),
    .method([String].self, returning: Void.self, isAsync: true),
    .getter(Int.self)
)
```

Construction throws `StubError` when the protocol or a requirement shape cannot
be supported. Automatic discovery resolves concrete runtime metadata for every
argument and result before allocating a witness table. When a linked
conformance is available, it also validates every signature component that can
be discovered reliably. Getter throwing behavior remains caller-supplied. No
construction path launches external tools.

## Supported features

- Instance methods and ordinary getters on a single,
  non-class-constrained protocol without inherited or associated requirements.
- Synchronous, throwing, async, and async-throwing methods, plus ordinary
  getters and explicitly described effectful getters.
- Fixed values and typed handlers of arbitrary arity.
- Genuinely suspending async handlers.
- Equality, predicate, wildcard, and capture matchers.
- At-least-once, exact-count, and never-called verification.
- Concurrent invocation after serial stub configuration.
- Integer, floating-point, direct aggregate, indirect, void, existential,
  optional, enum, tuple, metatype, and string values covered by ABI tests.

Enums, tuples, strings, and optionals do not need dedicated public APIs. Their
support depends on their ABI representation and the runtime metadata available
to the trampoline.

## Limitations

- Function and closure arguments or returns are rejected during construction
  because protocol witnesses require compiler-generated reabstraction. Use a
  small hand-written test double for protocols containing them.
- Protocol compositions are not supported; construct a separate stub for each
  protocol boundary.
- Read-write properties and class-constrained, inherited, associated-type,
  initializer, static, `_read`, and `_modify` requirements are rejected during
  construction.
- Automatic discovery cannot determine whether a getter throws. Describe
  throwing getters explicitly; async getters are rejected by automatic
  construction so their effects cannot be silently misclassified.
- Explicit requirement types, order, and effects must exactly match the
  declaration. A linked conformance is used to check every reliably
  discoverable component. Without resolvable witness symbols and concrete type
  metadata, Swift protocol metadata exposes only requirement count and kind;
  getter throwing behavior is never discoverable and remains caller-supplied.
- `any()` cannot currently synthesize a safe placeholder for an
  existential-typed argument. Match such arguments with a concrete conforming
  value.
- On x86_64, construction rejects async requirements whose arguments and
  indirect result consume all six general-purpose argument registers. That
  continuation boundary remains supported on arm64.
- Concrete/final methods and devirtualized calls are not protocol witness calls
  and are outside the library's scope.
- Keep `Stub` alive while its fabricated protocol value is in use.

## Architecture and further documentation

- [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
- [Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md)
- [Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
- [Migration from the pre-0.1 API](MIGRATION.md)
- [Roadmap to 0.1.0](ROADMAP.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes. See [SUPPORT.md](SUPPORT.md) for supported configurations
and [SECURITY.md](SECURITY.md) for private vulnerability reporting.

# swift-test-doubles

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Small, protocol-based test doubles for Swift—without macros, generated
conformers, or per-stub compiler invocations.

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

TestDoubles requires Swift 6.1. The runtime is exercised on macOS arm64 and
under Rosetta on x86_64. iOS and Linux are not release-supported yet.

## Common patterns

Use `returns` for a fixed response and `then` when behavior depends on the
arguments:

```swift
stub.when { $0.find(id: any()) }.then { (id: Int) in
    id.isMultiple(of: 2) ? "even" : "odd"
}

stub.when { try $0.read(path: any()) }.then { (path: String) throws in
    guard !path.hasPrefix("/private") else { throw PermissionError() }
    return "contents"
}
```

Async requirements use the same vocabulary. Suspending handlers run on the
caller's task, preserving task-local values, cancellation, priority, and actor
execution:

```swift
let stub = try Stub<any DataLoader>()

await stub.when { try await $0.fetch(path: any()) }.then {
    (path: String) async throws in
    try await fixtureServer.response(for: path)
}

let loader: any DataLoader = stub()
let value = try await loader.fetch(path: "/users/42")

await stub.verify { try await $0.fetch(path: equal("/users/42")) }
```

Verify the interactions that matter and state a count only when it adds value:

```swift
stub.verify { $0.find(id: any()) }
stub.verify(.exactly(3)) { $0.find(id: any()) }
stub.verify(.never) { $0.reset() }
```

Use `any()` for a wildcard, `equal(_:)` for equality, and `matching` for a
predicate. More specific registrations win: explicit equality, literal,
predicate, then wildcard or capture. The first registration wins a specificity
tie.

```swift
stub.when { $0.find(id: any()) }.returns("fallback")
stub.when { $0.find(id: matching(description: "positive", where: { $0 > 0 })) }
    .returns("member")
stub.when { $0.find(id: equal(1)) }.returns("admin")

let captor = ArgumentCaptor<Int>()
stub.verify { $0.find(id: captor.capture()) }
#expect(captor.values == [1])
```

Literal arguments use a best-effort textual comparison. Use `equal(_:)` when
equality semantics matter.

## Construction

The zero-argument initializer discovers requirement signatures from a real
conformer linked into the test process:

```swift
let stub = try Stub<any UserRepository>()
```

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
let stub = try Stub<any DataLoader>(
    .method(
        String.self,
        returning: Data.self,
        isThrowing: true,
        isAsync: true
    )
)
```

Construction throws `StubError` when the protocol or a requirement shape cannot
be supported. Automatic discovery resolves concrete runtime metadata for every
argument and result before allocating a witness table. When a linked
conformance is available, it also validates every signature component that can
be discovered reliably. Getter throwing behavior remains caller-supplied. No
construction path launches external tools.

## Supported feature set

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

## Known limitations

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

## Documentation

- [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
- [Stub](Sources/TestDoubles/Documentation.docc/Articles/StubGuide.md)
- [Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
- [Migration from the pre-0.1 API](MIGRATION.md)
- [Roadmap to 0.1.0](ROADMAP.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes.

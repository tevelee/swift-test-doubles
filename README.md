# swift-test-doubles

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Protocol-based test doubles for Swift, with no macros, generated conformer
source, or per-stub `swiftc` compilation.

`RuntimeStub` fabricates a protocol conformance and routes its witness calls
through a fixed runtime trampoline. The result is a compact arrange/act/assert
API for synchronous, throwing, and async requirements:

```swift
let stub = RuntimeStub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("guest")
stub.when { $0.find(id: equal(42)) }.returns("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }.wasCalled()
```

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

TestDoubles currently requires Swift 6.1. The runtime is exercised on macOS
arm64 and under Rosetta on x86_64. The package manifest still admits iOS while
platform validation is finalized; iOS and Linux are not release-supported yet.

## Stubbing behavior

Use `returns` for a fixed value and `then` when behavior depends on arguments or
can throw:

```swift
stub.when { $0.find(id: any()) }.then { (id: Int) in
    id.isMultiple(of: 2) ? "even" : "odd"
}

stub.when { try $0.read(path: any()) }.then { (path: String) throws in
    guard path.hasPrefix("/private") == false else {
        throw PermissionError()
    }
    return "contents"
}
```

Typed handlers accept arbitrary arity through parameter packs. A raw `[Any]`
handler remains available for dynamic cases.

Async and async-throwing requirements use the same vocabulary. An async `then`
handler may suspend on the caller's task, preserving task-local values,
cancellation, priority, and actor execution:

```swift
let stub = RuntimeStub<any DataLoader>()

await stub.when { try await $0.fetch(path: any()) }.then {
    (path: String) async throws in
    try await fixtureServer.response(for: path)
}

let loader: any DataLoader = stub()
let value = try await loader.fetch(path: "/users/42")

await stub.verify { try await $0.fetch(path: any()) }.wasCalled()
```

## Matchers and capture

The most specific matching response wins: exact values outrank predicates,
which outrank `any()`.

```swift
stub.when { $0.find(id: any()) }.returns("fallback")
stub.when { $0.find(id: any(where: { $0 > 0 })) }.returns("member")
stub.when { $0.find(id: equal(1)) }.returns("admin")

let captor = ArgumentCaptor<Int>()
stub.verify { $0.find(id: captor.capture()) }.wasCalled()
#expect(captor.values == [1])
```

## Verification

```swift
stub.verify { $0.find(id: any()) }.wasCalled()
stub.verify { $0.find(id: any()) }.wasCalled(times: 3)
stub.verify { $0.reset() }.wasNotCalled()

stub.verify { $0.save(name: any(), age: any()) }.withArgs {
    (name: String, age: Int) in
    #expect(name.isEmpty == false)
    #expect(age > 0)
}
```

## Creating the conformance

The zero-configuration initializer discovers requirement signatures from a real
conformer already linked into the test process:

```swift
let stub = RuntimeStub<any UserRepository>()
```

When no conformer is linked, TestDoubles can currently extract signatures from
an importable Swift module or accept explicit typed requirement slots:

```swift
let extracted = try RuntimeStub<any PrototypeCalculator>.makeFromModule()

let explicit = try RuntimeStub<any PrototypeCalculator>.make(
    .method(Int.self, Int.self, returns: Int.self),
    .method(Int.self, returns: String.self),
    .getter(Int.self)
)
```

`makeFromModule()` launches `swift symbolgraph-extract` from the host toolchain.
The zero-configuration and explicit-requirement paths do not launch external
tools.

These construction APIs are under review before `0.1.0`; see
[ROADMAP.md](ROADMAP.md) for the planned simplification.

## Supported feature set

- Protocol methods, getters, and setters.
- Synchronous, throwing, async, and async-throwing requirements.
- Immediate values and typed or raw dynamic handlers.
- Genuinely suspending async handlers.
- Exact, predicate, wildcard, and capture matchers.
- Called, exact-count, never-called, argument, and order verification.
- Concurrent invocation after serial stub configuration.
- Integer, floating-point, direct aggregate, indirect, void, existential,
  optional, enum, tuple, and metatype values covered by focused ABI tests.

Swift types such as enums, tuples, strings, and optionals do not each require a
separate public API. They are supported according to their ABI representation
and the runtime metadata available to the trampoline.

## Known limitations

- Function and closure requirements are rejected during construction because
  protocol witnesses require compiler-generated closure reabstraction. Use a
  small hand-written test double for protocols containing them.
- On x86_64, invoking an async requirement with six integer-class arguments
  crosses an unhandled continuation-register boundary. That shape is currently
  supported on arm64 only.
- Concrete functions, concrete or final methods, and devirtualized calls are not
  protocol witness calls and are outside the library's scope. Introduce a
  protocol boundary or use a dedicated replacement tool.
- Keep `RuntimeStub` alive as long as its fabricated protocol value is in use.

The release contract will narrow platform claims and convert preventable runtime
failures into construction-time diagnostics before `0.1.0`.

## Documentation

- [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
- [RuntimeStub](Sources/TestDoubles/Documentation.docc/Articles/RuntimeStub.md)
- [Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
- [Roadmap to 0.1.0](ROADMAP.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes.

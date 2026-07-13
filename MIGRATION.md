# Migration to the minimum runtime API

The pre-0.1 API was intentionally reduced before its first stable release. The
runtime trampoline remains the implementation; this migration removes alternate
ways to express the same operation and low-level runtime details from user code.

## Construction

| Before | Now |
| --- | --- |
| `RuntimeStub<any P>()` | `try Stub<any P>()` |
| `RuntimeStub<any P>.make()` | `try Stub<any P>()` |
| `makeFromModule()` | Pass explicit `Stub.Requirement` values |
| `Slot` / `MethodDescriptor` | `Stub.Requirement` |
| `.method(..., returns: R.self)` | `.method(..., returning: R.self)` |
| `.setter(...)` | Use a small hand-written double for read-write protocols |
| `describe()` / `setupScaffold()` / `diagnose()` | Handle `StubError` from construction |

Construction is always throwing. With no requirements, it uses a linked
conformer. With requirements, it fabricates the conformance without invoking
`swift symbolgraph-extract` or another external tool.

```swift
let automatic = try Stub<any UserRepository>()

let explicit = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

## Stubbing

| Before | Now |
| --- | --- |
| `thenAsync` | `then` with an async closure |
| `when { ... } then: { ... }` | `when { ... }.then { ... }` |
| Raw `[Any]` handler | A typed parameter-pack handler |

`returns` keeps the same call-site spelling and now captures one fixed value.
Use `then` for per-call evaluation. Both `then` overloads accept throwing
closures, so nonthrowing and throwing handlers share the same spelling.

```swift
await stub.when { try await $0.load(url: any()) }.then {
    (url: String) async throws in
    try await fixtures.load(url)
}
```

## Verification

| Before | Now |
| --- | --- |
| `.verify { ... }.wasCalled()` | `.verify { ... }` |
| `.wasCalled(times: n)` | `.verify(.exactly(n)) { ... }` |
| `.wasNotCalled()` / `verify(never:)` | `.verify(.never) { ... }` |
| `.withArgs { ... }` | `ArgumentCaptor` |
| `calls` / `RecordedCall` | Direct count verification and captors |
| `verifyOrder` | Removed from the 0.1 scope |
| `when(setting:)` / `verify(setting:)` | Use a small hand-written double |

Order verification was removed because its previous implementation covered only
a subset of invocation kinds and ignored argument matchers. It can return later
only with a complete contract.

Setter stubbing was removed because Swift read-write protocol properties carry
a `_modify` coroutine witness that the runtime cannot fabricate safely.

## Matchers

The public matcher vocabulary is now `any()`, `equal(_:)`,
`matching(description:where:)`, and `ArgumentCaptor.capture()`. `Matcher`,
`ParameterMatcher`, `any(where:)`, and `capture(into:)` were removed.

```swift
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}.returns("member")
```

Literal matching remains available as a convenience, but uses best-effort
textual comparison. Use `equal(_:)` when equality semantics matter.

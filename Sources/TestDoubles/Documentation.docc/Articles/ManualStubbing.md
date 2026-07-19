# Manual Stubbing

Write a small conforming struct and get full control over your test doubles.

## Overview

``ManualStub`` is the escape hatch for protocols ``Stub`` can't represent:
new language features, requirement shapes the runtime trampoline does not
cover, or platforms the runtime strategy does not run on. You write a struct
that conforms to your protocol and delegates each requirement to a
``ManualStub``. The library handles stub registration, argument matching,
call recording, and verification through the same recorder ``Stub`` uses
internally.

Construction diagnostics that report an unsupported protocol shape,
unavailable executable trampoline, or unsupported runtime type kind point here
as the supported fallback. A missing linked conformer is different: first
anchor an existing conformance as a protocol existential or provide explicit
``Stub/Requirement`` values. Use `ManualStub` when no conformer exists or the
requirement itself is outside ``Stub``'s runtime boundary.

- A protocol requirement uses a shape ``Stub`` rejects during construction —
  see ``StubError`` and <doc:StubContract>.
- You need the stub to work on a platform the runtime trampoline doesn't run
  on, such as a physical Apple device.
- You want explicit, readable stub implementations that serve as living
  documentation for a core domain protocol.

### Quick Start

```swift
// 1. Define your stub struct
struct MyServiceStub: MyService, StubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.fetch(id: id) }   // non-throwing: base route
    func reset() { stub.reset() }
    func save(_ item: Item) throws { try stub.throwing.save(item) } // throwing: .throwing route
}

// 2. Configure and use in your test
let stub = ManualStub<MyServiceStub>()
stub.when { $0.fetch(id: equal(42)) }.thenReturn("Alice")

let sut: any MyService = stub()
// sut.fetch(id: 42) == "Alice"

// 3. Verify
stub.verify { $0.fetch(id: any()) }
```

### Forward requirements

Non-throwing methods and getters, synchronous or asynchronous, use the base
dynamic-member route:

```swift
func fetch(id: Int) -> String { stub.fetch(id: id) }
func reset() { stub.reset() }
var count: Int { stub.count }
```

Read-write properties forward their getter and setter through the same dynamic
member name:

```swift
var displayName: String {
    get { stub.displayName }
    set { stub.displayName = newValue }
}
```

Throwing methods and throwing getters use ``ManualStub/throwing``:

```swift
func save(_ item: Item) throws { try stub.throwing.save(item) }
var token: String { get throws { try stub.throwing.token } }
```

Swift can overload a function purely on `async`, but it cannot overload a
subscript getter purely on `async` or `throws`. Splitting throwing access onto
``ManualThrowingRoute`` keeps non-throwing and throwing forwarding paths
separate while allowing both synchronous and asynchronous method calls.

Use the explicit fallback methods when a dynamic-member route cannot express
the requirement, especially async property getters:

```swift
var status: Status {
    get async { await stub.asyncCall() }
}
```

The fallback methods default their `function` parameter to `#function`, so the
forwarding body usually does not need to repeat the requirement name.

For typed throws, use the explicit fallback and pass the declared error type to
`throwing:`. This preserves the restricted error channel for synchronous,
asynchronous, value-returning, and `Void` requirements:

```swift
enum ServiceError: Error { case unavailable }

var token: String {
    get throws(ServiceError) {
        try stub.throwingCall(throwing: ServiceError.self)
    }
}

func refresh(_ id: Int) async throws(ServiceError) -> Item {
    try await stub.asyncThrowingCall(
        id,
        throwing: ServiceError.self
    )
}
```

The configured handler must throw exactly that error type. A different error
cannot cross Swift's typed-throws boundary, so ManualStub fails closed with an
expected and actual type diagnostic. Use the untyped `.throwing` dynamic-member
route only for requirements declared with ordinary untyped `throws`.

When overloads have the same labels, result, and effects but different argument
types, use a ``ManualRouteID`` with the explicit fallback. The route keeps the
static types separate while diagnostics continue to show the ordinary
`#function` signature:

```swift
func render(_ value: Int) -> String {
    stub.call(value, route: ManualRouteID(argumentTypes: Int.self))
}

func render(_ value: String) -> String {
    stub.call(value, route: ManualRouteID(argumentTypes: String.self))
}
```

The same route parameter composes with typed throws:

```swift
func load(_ id: Int) throws(ServiceError) -> Item {
    try stub.throwingCall(
        id,
        route: ManualRouteID(argumentTypes: Int.self),
        throwing: ServiceError.self
    )
}
```

### Tradeoffs

ManualStub is ordinary Swift. It avoids runtime metadata, witness table
patching, and runtime code generation entirely.

That makes it the best fit for:

- protocols with requirement shapes the runtime trampoline doesn't cover
- platforms the runtime strategy doesn't run on
- protocols with language features the runtime strategies intentionally skip

The cost is boilerplate: every protocol requirement needs a forwarding
implementation, and those forwarding methods must stay in sync with the
protocol by hand. There is no compile-time check that a forwarding body's
dynamic-member name matches the requirement it forwards for. A typo compiles
and simply becomes a distinct, never-stubbed entry, surfacing as a "No stub
configured" failure the first time it is exercised.

### Workarounds

- Two requirements sharing a base name but differing only in argument labels
  are disambiguated automatically. The interned key includes labels, the
  same way `#function` does (`"save(item:)"` vs. `"save(name:)"`).
- Sync/async overloads and overloads distinguished by result type use separate
  recorder entries even when their printed signature is identical.
- Overloads that have the same labels, effects, and result type but differ only
  in argument types use typed ``ManualRouteID`` values with the explicit
  fallback methods. Dynamic-member syntax still erases argument types to `Any`,
  so it cannot infer this distinction automatically.
- A getter and setter on the same property intern to distinct keys
  (`"count"` vs. `"count="`), so stubbing one never interferes with the
  other.
- Keep one stub instance per test. The recorder is mutable test-local state.

### Key Types

- ``StubConformer`` — protocol your stub struct conforms to; provides
  `init(stub:)` for free via the synthesized memberwise initializer.
- ``ManualStub`` — the stub container; holds registrations and the call log,
  and provides `when`, immediate or eventual `verify`, `verifyInOrder`,
  `verifyNoMoreInteractions`, and `clearRecordedInvocations` with the same
  semantics as ``Stub``.
- ``ManualRouteID`` — a readable signature plus static argument-type identity
  for explicit forwarding of otherwise indistinguishable overloads.
- ``ManualMethodProxy`` — forwarding proxy for non-throwing method calls.
- ``ManualThrowingRoute`` — forwarding route for throwing methods and getters.
- ``ManualThrowingMethodProxy`` — forwarding proxy for throwing method calls.

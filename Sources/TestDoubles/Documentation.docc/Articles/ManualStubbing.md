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
struct MyServiceStubConformer: MyService, ManualStubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.requirements.fetch(id: id) }
    func reset() { stub.requirements.reset() }
    func save(_ item: Item) throws {
        try stub.throwingRequirements.save(item)
    }
}

typealias MyServiceStub = ManualStub<MyServiceStubConformer>

// 2. Configure and use in your test
let stub = MyServiceStub()
stub.when { $0.fetch(id: Match.equal(42)) }.thenReturn("Alice")

let sut: any MyService = stub()
// sut.fetch(id: 42) == "Alice"

// 3. Verify
stub.verify { $0.fetch(id: Match.any()) }
```

### Generate a conformer with the optional command plugin

For ordinary protocol requirements, invoke the `ManualStubGenerator` command
plugin instead of writing the forwarding struct. It is disabled by default;
from the TestDoubles package checkout, enable its `ManualStubGenerator` trait:

```sh
swift package --traits ManualStubGenerator plugin \
  --allow-writing-to-package-directory generate-manual-stub \
  WeatherService Sources/WeatherService.swift \
  Tests/WeatherServiceStub.swift
```

The plugin emits a forwarding implementation named
`WeatherServiceStubConformer` and the controller alias `WeatherServiceStub`.
Create the alias directly in a test. Generated methods and subscripts use the
static types of their arguments automatically, so overloads that differ only by
argument type remain independent. Typed-throws requirements preserve their
declared failure type instead of erasing it to ordinary `throws`.

The generator deliberately rejects static and initializer requirements. Both
need process-wide state rather than the test-local recorder owned by a
``ManualStub``, which makes an implicit generated implementation unsafe when
tests run in parallel. Write a custom conformer when your application has an
explicitly scoped way to satisfy one of those requirements. Recognized
declarations that cannot be forwarded also produce an error instead of being
silently omitted.
The plugin uses no parser-library dependency, and clients that do not invoke it
neither build nor run it.

### Generate a conformer with `@Stubbable`

For the same ordinary requirement shapes, the `StubbableMacros` trait provides
an annotation macro. This feature is independently disabled by default because
it depends on SwiftSyntax. Enable it only in packages that want compile-time
generation:

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles.git",
    from: "0.0.2",
    traits: ["StubbableMacros"]
)
```

Add the macro product to the target that declares the protocol:

```swift
.target(
    name: "Weather",
    dependencies: [
        .product(name: "TestDoublesMacros", package: "swift-test-doubles")
    ]
)
```

Then annotate the protocol and configure the generated `ManualStub` normally:

```swift
import TestDoubles
import TestDoublesMacros

@Stubbable
protocol WeatherService {
    func forecast(for city: String) -> String
}

let stub = WeatherServiceStub()
stub.when { $0.forecast(for: "Budapest") }.thenReturn("Sunny")

let service: any WeatherService = stub()
// service.forecast(for: "Budapest") == "Sunny"
```

`@Stubbable` emits `WeatherServiceStubConformer` and the
`WeatherServiceStub` controller alias.
The macro is deliberately a convenience layer over the same explicit
forwarding code as the command plugin: generated source stays inspectable, and
the hand-written ``ManualStub`` escape hatches remain available for requirement
shapes that need custom forwarding.

### Forward requirements

Non-throwing methods and getters, synchronous or asynchronous, use
``ManualStub/requirements``:

```swift
func fetch(id: Int) -> String { stub.requirements.fetch(id: id) }
func reset() { stub.requirements.reset() }
var count: Int { stub.requirements.count }
```

Read-write properties forward their getter and setter through the same dynamic
member name:

```swift
var displayName: String {
    get { stub.requirements.displayName }
    set { stub.requirements.displayName = newValue }
}
```

Throwing methods and throwing getters use
``ManualStub/throwingRequirements``:

```swift
func save(_ item: Item) throws {
    try stub.throwingRequirements.save(item)
}
var token: String {
    get throws { try stub.throwingRequirements.token }
}
```

Swift can overload a function purely on `async`, but it cannot overload a
subscript getter purely on `async` or `throws`. Splitting throwing access onto
``ManualThrowingRequirementRoute`` keeps non-throwing and throwing forwarding
paths separate while allowing both synchronous and asynchronous method calls.
The namespace also prevents protocol requirements such as `reset()` from
colliding with ``ManualStub``'s own control API.

Use the explicit fallback methods when a dynamic-member route cannot express
the requirement, especially async property getters:

```swift
var status: Status {
    get async { await stub.call() }
}
```

The synchronous and asynchronous fallback overloads are both named `call`.
They default their `function` parameter to `#function`, so the forwarding body
usually does not need to repeat the requirement name.

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
    try await stub.throwingCall(
        id,
        throwing: ServiceError.self
    )
}
```

The configured handler must throw exactly that error type. A different error
cannot cross Swift's typed-throws boundary, so `ManualStub` fails closed with an
expected and actual type diagnostic. Use the untyped
`throwingRequirements` dynamic-member route only for requirements declared
with ordinary untyped `throws`.

When overloads have the same labels, result, and effects but different argument
types, the explicit fallback infers a distinct route from each argument's
static type:

```swift
func render(_ value: Int) -> String {
    stub.call(value)
}

func render(_ value: String) -> String {
    stub.call(value)
}
```

The same inference composes with typed throws:

```swift
func load(_ id: Int) throws(ServiceError) -> Item {
    try stub.throwingCall(
        id,
        throwing: ServiceError.self
    )
}
```

### Tradeoffs

ManualStub is ordinary Swift. It avoids runtime metadata, witness table
patching, and runtime code generation entirely.

It also stays outside the internal runtime implementation: manual forwarding
talks only to TestDoubles' recording semantics, never to Echo reflection,
fabricated witness tables, executable trampolines, or ABI frame types.

That makes it the best fit for:

- protocols with requirement shapes the runtime trampoline doesn't cover
- platforms the runtime strategy doesn't run on
- protocols with language features the runtime strategies intentionally skip

The cost of a hand-written conformer is boilerplate: every protocol requirement
needs a forwarding implementation, and those forwarding methods must stay in
sync with the protocol. The command plugin and `@Stubbable` remove that
boilerplate for ordinary declarations; unusual syntax can still require a
hand-written conformer. There is no compile-time check that a hand-written
forwarding body's dynamic-member name matches the requirement it forwards. A
typo compiles and simply becomes a distinct, never-stubbed entry, surfacing as
a "No stub configured" failure the first time it is exercised.

### Workarounds

- Two requirements sharing a base name but differing only in argument labels
  are disambiguated automatically. The interned key includes labels, the
  same way `#function` does (`"save(item:)"` vs. `"save(name:)"`).
- Sync/async overloads and overloads distinguished by result type use separate
  recorder entries even when their printed signature is identical.
- Overloads that have the same labels, effects, and result type but differ only
  in argument types use the explicit `call` or `throwingCall` fallback. Swift
  parameter packs preserve the static argument types and infer the route
  automatically. Hand-written dynamic-member syntax still erases argument
  types to `Any`, so it cannot infer this distinction automatically.
- A getter and setter on the same property intern to distinct keys
  (`"count"` vs. `"count="`), so stubbing one never interferes with the
  other.
- Keep one stub instance per test. The recorder is mutable test-local state.

### Key Types

- ``ManualStubConformer`` — protocol your stub struct conforms to; provides
  `init(stub:)` for free via the synthesized memberwise initializer.
- ``ManualStub`` — the stub container; holds registrations and the call log,
  and provides `when`, immediate or eventual `verify`, `verifyInOrder`,
  `verifyNoMoreInteractions`, `clearRecordedInvocations`, and `reset` with the
  same semantics as ``Stub``.
- ``ManualRequirementRoute`` — namespace for non-throwing protocol
  requirements.
- ``ManualThrowingRequirementRoute`` — namespace for throwing methods and
  getters.

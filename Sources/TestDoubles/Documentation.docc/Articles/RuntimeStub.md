# RuntimeStub

Trampoline-backed stubs for protocol existentials — no boilerplate struct required.

## Overview

RuntimeStub uses a fixed architecture trampoline to intercept protocol witness calls. In zero-config mode it discovers method signatures from an existing witness table; with ``RuntimeStub/makeFromModule(moduleName:)`` or explicit ``Slot``/``MethodDescriptor`` values it fabricates the conformance table directly, so no real conformer is needed.

For the complete call path, frame layout, register contracts, metadata
marshalling, ownership model, debugger breakpoints, and maintenance rules, see
<doc:TrampolineArchitecture>.

**When to use RuntimeStub:**
- You want the fastest test-authoring experience with minimal boilerplate.
- Your test binary already links a real conformer for zero-config discovery, or the protocol's compiled Swift module is importable.
- You can provide explicit requirement signatures when module extraction is not available.
- You're on a supported arm64 or x86_64 Apple target. The assembly has ELF symbol support, but Linux remains unverified.

**Requirement:** The zero-config initializer needs a real conformer somewhere in the linked binary so it can discover signatures. ``RuntimeStub/makeFromModule(moduleName:)`` extracts signatures from `swift symbolgraph-extract`; the explicit ``Slot`` and ``MethodDescriptor`` initializers use caller-provided signatures.

**Dependency:** RuntimeStub requires the `Echo` package (pulled in automatically when the `RuntimeStub` trait is active).

**Async:** RuntimeStub supports async and async-throwing requirements through a
dedicated continuation trampoline. Use `returns` or `then:` for immediate
responses and `thenAsync:` when the configured handler must suspend.

For the full decision matrix, see <doc:StrategyGuide>.

## Installation

RuntimeStub is enabled by default:

```swift
// Package.swift — default (ManualStub + RuntimeStub)
.package(url: "https://github.com/tevelee/swift-test-doubles", from: "1.0.0")
```

To pull in RuntimeStub _only_:

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["RuntimeStub"]
)
```

## Quick Start

```swift
// Zero config — signatures auto-discovered from the witness table
let stub = RuntimeStub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("Alice")
stub.when { $0.count }.returns(1)

let sut: any UserRepository = stub()
assert(sut.find(id: 99) == "Alice")

// Verify
stub.verify { $0.find(id: any()) }.wasCalled()
```

When no conformer exists, extract signatures from the compiled module:

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.makeFromModule()
```

Or provide the requirement slots directly:

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.make(
    .method(Int.self, Int.self, returns: Int.self), // add
    .method(Int.self, returns: String.self),        // describe
    .getter(Int.self)                               // precision
)
```

Explicit slots preserve real Swift type names for metadata-driven marshalling.
Use the `args:` overload for high-arity methods, throwing requirements, and
indirect struct returns:

```swift
let stub = try RuntimeStub<any Gateway>.make(
    .method(
        args: [Int.self, Money.self, String.self, Bool.self],
        returns: Receipt.self,
        throws: true
    )
)
```

Mark explicit async slots with `async: true`:

```swift
let stub = try RuntimeStub<any AsyncDataLoader>.make(
    .method(String.self, returns: String.self, throws: true, async: true),
    .method([String].self, async: true),
    .getter(Int.self)
)
```

If you do not know the slot order, ask RuntimeStub to describe the protocol and
generate an explicit setup scaffold:

```swift
let report = try RuntimeStub<any PrototypeCalculator>.describe()
print(report)

let setup = try RuntimeStub<any PrototypeCalculator>.setupScaffold()
print(setup)
```

Example scaffold:

```swift
let stub = try RuntimeStub<any PrototypeCalculator>.make(
    .method(args: [Int.self, Int.self], returns: Int.self), // add(_:_:)
    .method(args: [Int.self], returns: String.self),        // describe(_:)
    .getter(Int.self)                                       // precision
)
```

## Diagnosing Missing Conformers

```swift
let diagnostics = RuntimeStub<any MyProto>.diagnose()
print(diagnostics.notes)  // tells you what's missing and how to fix it
```

## Signature Sources

RuntimeStub needs argument and return metadata before it can marshal values.
Pick one source:

| Source | API | Needs real conformer | Needs toolchain | Best use |
|---|---|---|---|---|
| Existing witness table | `RuntimeStub<any P>()` | Yes | No | App/test binary already links an implementation |
| Swift module | `RuntimeStub<any P>.makeFromModule()` | No | Yes | Protocol module is importable |
| Explicit slots | `RuntimeStub<any P>.make(...)` | No | No | You know the requirement order |
| Method descriptors | `RuntimeStub<any P>.make(methods:)` | No | No | You need explicit slot indexes or names |

Explicit slots preserve real Swift type names:

```swift
let stub = try RuntimeStub<any SearchIndex>.make(
    .method(args: [String.self, Int.self], returns: [String].self),
    .getter(Bool.self)
)
```

## Tradeoffs

RuntimeStub is the fastest no-boilerplate path for protocol stubs. It does not
run `swiftc` at test startup, and explicit/module signatures do not need a real
conformer in the binary.

The cost is ABI coupling. RuntimeStub depends on Swift runtime metadata,
protocol descriptor layout, and small assembly stubs for the supported
architectures. Async witness entries use compact function descriptors.
Immediate responses invoke the caller's continuation directly; suspending
handlers chain a Swift async frame into the caller's existing task before
resuming that continuation.

```swift
await stub.when({ try await $0.load(id: any()) }, thenAsync: { args in
    let id = args[0] as! Int
    return try await fixtureStore.load(id: id)
})
```

`thenAsync:` preserves the caller task's task-local values, priority,
cancellation state, and actor executor. Use the distinct label to make genuine
suspension explicit; `then:` remains the lower-overhead immediate path.

Use RuntimeStub when:

- tests need short setup and no hand-written conformer
- configured async responses may be immediate or genuinely suspending
- argument and return types have runtime metadata available
- the dependency is passed as an existential protocol value

Avoid RuntimeStub when:

- the protocol relies on `_read` or `_modify` coroutine accessors
- a requirement accepts or returns a closure value
- calls are made to concrete functions or concrete methods instead of protocol
  witnesses
- the same stub must be configured or verified from multiple tasks at once

## Workarounds

- No conformer: use `makeFromModule()` or explicit slots.
- Module extraction unavailable: use explicit slots or ``CompiledStub``.
- Unsupported runtime ABI shape: use ``CompiledStub`` or implement it directly
  in a hand-written ``ManualStub`` method.
- Concrete function or final method: use ``DynamicReplacementCompiler`` if the
  implementation is built with implicit dynamic.
- Type metadata cannot be resolved: use explicit slots with concrete
  `Any.Type` values, or use ``CompiledStub``.
- Order verification with arguments: combine `verifyOrder` with separate
  `verify` assertions for the argument values.

## Key Types

- ``RuntimeStub`` — the stub container; wraps a `StubRecorder` and manages the witness table override.
- ``Slot`` — describes a protocol requirement by real Swift argument and return types.
- ``DiscoveredSignature`` — returned by the signature discovery engine.
- ``RuntimeStubError`` — thrown when stub creation fails.

The C/assembly and internal Swift method map is documented in
<doc:TrampolineArchitecture>.

## Limitations

- Runtime marshalling depends on real Swift type metadata. If metadata cannot
  be resolved for a requirement, use explicit ``Slot`` descriptors or
  ``CompiledStub``.
- Suspending handlers require `thenAsync:`. The existing `returns` and `then:`
  APIs intentionally remain immediate.
- Fabricated conformances are used to build the returned existential directly.
  Do not rely on unrelated `as?` runtime conformance lookup for arbitrary
  payload values.

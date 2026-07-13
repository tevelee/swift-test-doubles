# ManualStub

Write a small conforming struct and get full control over your test doubles.

## Overview

ManualStub is the zero-dependency strategy. You write a struct that conforms to your protocol and delegates each method to a `Stub<Self>` instance. The library handles stub registration, argument matching, call recording, and verification.

**When to use ManualStub:**
- You want no external dependencies (`Echo` is not pulled in).
- You need the stub to work on all platforms (Linux, iOS, watchOS, etc.).
- You want explicit, readable stub implementations that serve as living documentation.
- You're stubbing a protocol that has no real conformer in your test binary.

**Requirement:** The ManualStub trait must be enabled (it is on by default).

For the full decision matrix, see <doc:StrategyGuide>.

## Installation

ManualStub is enabled by default. No additional configuration needed:

```swift
// Package.swift — default (ManualStub + RuntimeStub)
.package(url: "https://github.com/tevelee/swift-test-doubles", from: "1.0.0")
```

To pull in ManualStub _only_ (no Echo dependency):

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["ManualStub"]
)
```

## Quick Start

```swift
// 1. Define your stub struct
struct MyServiceStub: MyService, StubConformer {
    let stub: Stub<Self>

    func fetch(id: Int) -> String { stub.fetch(id: id) }  // Approach A
    func reset()                  { stub.call() }          // Approach B
}

// 2. Configure and use in your test
let stub = Stub<MyServiceStub>()
stub.when { $0.fetch(id: equal(42)) }.returns("Alice")

let sut: any MyService = stub()
assert(sut.fetch(id: 42) == "Alice")

// 3. Verify
stub.verify { $0.fetch(id: any()) }.wasCalled()
```

**Approach A** (`@dynamicMemberLookup`) works for labeled non-void methods and property getters.  
**Approach B** (`stub.call(...)`) is required for void zero-argument methods, throwing methods, and async methods.

## Tradeoffs

ManualStub is ordinary Swift. It avoids runtime metadata, witness table
patching, runtime compilation, and toolchain discovery.

That makes it the best fit for:

- cross-platform test suites
- highly concurrent systems where you want to add your own synchronization
- protocols with async requirements
- protocols with language features the runtime strategies intentionally skip

The cost is boilerplate. Every protocol requirement needs a forwarding
implementation, and those forwarding methods must stay in sync with the
protocol.

## Tips

- Prefer ManualStub for core domain protocols that are stable and important
  enough to document with a hand-written test double.
- Keep forwarding bodies boring. If a forwarding method starts accumulating
  logic, move that behavior into test configuration with `when`.
- Use Approach B for throwing and async methods even when Approach A appears to
  compile; it is more predictable across Swift versions.
- Keep one stub instance per test. The recorder is mutable test-local state.

## Workarounds

- If a protocol is too large to forward manually, use ``RuntimeStub`` for
  covered runtime ABI shapes, including suspending async handlers, or
  ``CompiledStub`` on macOS for requirements outside that coverage.
- If the system under test stores the dependency and uses it later, keep the
  `Stub` object alive for the whole test.
- If argument labels make Approach A awkward, use `stub.call(..., function:)`
  explicitly and pass the exact method name.

## Key Types

- ``StubConformer`` — protocol your stub struct conforms to; provides `Stub<Self>`.
- ``Stub`` — the stub container; holds registrations and the call log.

# CompiledStub

Compile a conforming type at test startup using `swiftc` — no real conformer required.

## Overview

CompiledStub invokes the Swift compiler at test startup to synthesize a concrete type that conforms to your protocol. The generated type calls `MockBridge` for every method, routing dispatch back into the same `StubRecorder` infrastructure used by RuntimeStub.

**When to use CompiledStub:**
- The protocol lives in a pre-compiled framework your tests import but don't link a concrete type for.
- `RuntimeStub` fails with `noConformanceFound` because no conformer is in the binary.
- You're on **macOS** (other platforms are not supported — `swiftc` availability is macOS-only).

**Requirement:** macOS. The `CompiledStub` trait automatically enables `RuntimeStub`.

**Overhead:** The first use per protocol triggers a `swiftc` invocation — typically 1–2 seconds. Subsequent uses within the same test run are free (the dylib is cached).

## Installation

CompiledStub is opt-in:

```swift
// Package.swift
.package(
    url: "https://github.com/your-org/swift-test-doubles",
    from: "1.0.0",
    traits: ["ManualStub", "RuntimeStub", "CompiledStub"]
)
```

## Quick Start

```swift
// No conformer needed — the library compiles one for you
let stub = try RuntimeStub<any PrototypeCalculator>.compiled {
    $0.method("add",      args: [.int(), .int()], returns: .int)
    $0.method("describe", args: [.int()],          returns: .string)
    $0.getter("precision", type: .int)
}

stub.when { $0.add(1, 2) }.returns(3)
stub.when { $0.precision }.returns(10)

let sut: any PrototypeCalculator = stub()
assert(sut.add(1, 2) == 3)
```

## Automatic Fallback

When you use the default `.auto` strategy, `RuntimeStub` compiles a stub if the conformer is missing; otherwise it uses the existing conformer with thunks. This lets you write a single test that works whether or not a real conformer is present:

```swift
let stub = RuntimeStub<any MyService>()  // .auto is the default
```

## Key Types

- ``RuntimeStub`` — use the `.compiled(_:)` factory or `strategy: .compiled` initializer.
- ``DiscoveredSignature`` — describes the methods you want the compiled stub to implement.
- ``SignatureBuilder`` — DSL for building signature lists (used inside the `.compiled { }` closure).

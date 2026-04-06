# RuntimeStub

Zero-configuration stubs backed by witness table reflection — no boilerplate struct required.

## Overview

RuntimeStub discovers protocol method signatures at runtime by inspecting the Swift witness table and uses pre-generated thunks to intercept calls. No source generation, no macros, no conforming struct to write.

**When to use RuntimeStub:**
- You want the fastest test-authoring experience with minimal boilerplate.
- Your test binary already links a real conformer for the protocol (e.g., the implementation framework is embedded in the test target).
- You're on any Apple platform or Linux.

**Requirement:** A real conformer for the protocol must exist somewhere in the linked binary. If it doesn't, `RuntimeStub` will throw `RuntimeStubError.noConformanceFound` at construction time. Use `RuntimeStub.diagnose()` to get a human-readable explanation.

**Dependency:** RuntimeStub requires the `Echo` package (pulled in automatically when the `RuntimeStub` trait is active).

## Installation

RuntimeStub is enabled by default:

```swift
// Package.swift — default (ManualStub + RuntimeStub)
.package(url: "https://github.com/your-org/swift-test-doubles", from: "1.0.0")
```

To pull in RuntimeStub _only_:

```swift
.package(
    url: "https://github.com/your-org/swift-test-doubles",
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

## Diagnosing Missing Conformers

```swift
let diagnostics = RuntimeStub<any MyProto>.diagnose()
print(diagnostics.notes)  // tells you what's missing and how to fix it
```

## Key Types

- ``RuntimeStub`` — the stub container; wraps a `StubRecorder` and manages the witness table override.
- ``Slot`` — describes a protocol requirement by its ABI signature (for the slot-based initializer).
- ``DiscoveredSignature`` — returned by the signature discovery engine.
- ``RuntimeStubError`` — thrown when stub creation fails.

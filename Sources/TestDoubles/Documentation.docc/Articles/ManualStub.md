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

## Installation

ManualStub is enabled by default. No additional configuration needed:

```swift
// Package.swift — default (ManualStub + RuntimeStub)
.package(url: "https://github.com/your-org/swift-test-doubles", from: "1.0.0")
```

To pull in ManualStub _only_ (no Echo dependency):

```swift
.package(
    url: "https://github.com/your-org/swift-test-doubles",
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

## Key Types

- ``StubConformer`` — protocol your stub struct conforms to; provides `Stub<Self>`.
- ``Stub`` — the stub container; holds registrations and the call log.

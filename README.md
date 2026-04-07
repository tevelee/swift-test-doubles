# swift-test-doubles

[![CI](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml/badge.svg)](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Protocol-based test doubles for Swift — no macros, no code generation. Three strategies; pick the one that fits your project.

## Strategies

| | ManualStub | RuntimeStub | CompiledStub |
|---|---|---|---|
| **Platform** | All | All | macOS only |
| **Requires conformer in binary** | No | Yes | No |
| **Requires Echo** | No | Yes | Yes (via RuntimeStub) |
| **Test startup overhead** | None | None | ~1–2 s compile |

## Installation

### Default (ManualStub + RuntimeStub)

```swift
// Package.swift
.package(url: "https://github.com/tevelee/swift-test-doubles", from: "1.0.0")

// Target dependency
.product(name: "TestDoubles", package: "swift-test-doubles")
```

### ManualStub only (no Echo dependency)

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["ManualStub"]
)
```

### With CompiledStub (macOS, opt-in)

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["ManualStub", "RuntimeStub", "CompiledStub"]
)
```

---

## ManualStub

Write a small conforming struct and delegate to `Stub<Self>`. Works on all platforms; no real conformer needed; no external dependencies.

```swift
// 1. Define your stub
struct ServiceStub: ServiceProtocol, StubConformer {
    let stub: Stub<Self>
    func find(id: Int) -> String   { stub.find(id: id) }   // Approach A
    func reset()                    { stub.call() }          // Approach B
    func save(_ x: String) throws  { try stub.throwingCall(x) }
}

// 2. Configure and use
let stub = Stub<ServiceStub>()
stub.when { $0.find(id: equal(42)) }.returns("Alice")

let sut: any ServiceProtocol = stub()
assert(sut.find(id: 42) == "Alice")

// 3. Verify
stub.verify { $0.find(id: any()) }.wasCalled()
```

**Approach A** (`@dynamicMemberLookup`) — labeled non-void methods, property getters.  
**Approach B** (`stub.call(...)`) — void zero-arg methods, throwing, async.

---

## RuntimeStub

Zero configuration. Method signatures are discovered from the binary at runtime via witness table reflection. Requires the Echo package and at least one real conformer linked into your test binary.

```swift
let stub = RuntimeStub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("Alice")
stub.when { $0.count }.returns(1)

let sut: any UserRepository = stub()
assert(sut.find(id: 99) == "Alice")

stub.verify { $0.find(id: any()) }.wasCalled()
```

If setup fails, call `RuntimeStub.diagnose()` for a human-readable explanation:

```swift
let d = RuntimeStub<any MyProto>.diagnose()
print(d.notes)
```

---

## CompiledStub

Compile a conforming type at test startup using `swiftc`. No real conformer needed. macOS only; the first use per protocol takes ~1–2 s.

```swift
let stub = try CompiledStub<any PrototypeCalculator> {
    $0.method("add", args: [.int(), .int()], returns: .int)
    $0.method("describe", args: [.int()], returns: .string)
    $0.getter("precision", type: .int)
}

stub.when { $0.add(1, 2) }.returns(3)
stub.when { $0.precision }.returns(10)

assert(stub().add(1, 2) == 3)
```

---

## Matchers & Captors

```swift
stub.when { $0.find(id: any()) }.returns("default")          // any value
stub.when { $0.find(id: equal(42)) }.returns("exact")        // equality
stub.when { $0.find(id: any(where: { $0 > 0 })) }.returns("positive") // predicate

let captor = ArgumentCaptor<Int>()
stub.verify { $0.find(id: captor.capture()) }.wasCalled()
assert(captor.values == [42])
```

---

## Verification

```swift
stub.verify { $0.find(id: any()) }.wasCalled()           // at least once
stub.verify { $0.find(id: any()) }.wasCalled(times: 3)   // exactly N times
stub.verify(called: 2) { $0.find(id: any()) }            // concise form
stub.verify(never: { $0.reset() })                        // never called

stub.verify { $0.find(id: any()) }.withArgs { calls in
    assert(calls[0][0] as! Int == 99)
}
```

---

## Requirements

- Swift 6.1+
- macOS 13+ / iOS 16+

---

## Known Limitations

**RuntimeStub: large struct returns crash (SIGSEGV)**

`RuntimeStub` uses pre-generated ABI thunks that assume return values fit in ≤ 16 bytes (two machine words). Methods returning structs larger than 16 bytes will crash with a memory access violation when called through the stub. Use `ManualStub` or `CompiledStub` for protocols with such return types.

Affected signatures: any method returning a struct whose total size > 16 bytes. Examples: a struct with `String` + `Double` + `Bool`, or any struct containing two `String` fields.

**CompiledStub is macOS-only**

`swiftc` is not available on Linux or iOS simulators. Use `ManualStub` or `RuntimeStub` on other platforms.

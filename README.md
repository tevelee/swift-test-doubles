# swift-test-doubles

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Protocol-based test doubles for Swift — no macros, no code generation. Three protocol-stub strategies, plus dynamic replacement support when you control the implementation build.

## Strategies

| | ManualStub | RuntimeStub | CompiledStub |
|---|---|---|---|
| **Platform** | All | Apple arm64/x86_64; Linux unverified | macOS only |
| **Requires conformer in binary** | No | Zero-config only | No |
| **Requires Echo** | No | Yes | Yes (via RuntimeStub) |
| **Test startup overhead** | None | None | ~1–2 s compile |

## Documentation Map

- **Start here:** [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
- **Tradeoffs and workarounds:** [Strategy Guide](Sources/TestDoubles/Documentation.docc/Articles/StrategyGuide.md)
- **Runtime details:** [RuntimeStub](Sources/TestDoubles/Documentation.docc/Articles/RuntimeStub.md)
- **Trampoline internals:** [Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)
- **Compiled fallback:** [CompiledStub](Sources/TestDoubles/Documentation.docc/Articles/CompiledStub.md)
- **Concrete replacements:** [Dynamic Replacement](Sources/TestDoubles/Documentation.docc/Articles/DynamicReplacement.md)

## Installation

### Default (ManualStub + RuntimeStub)

```swift
// Package.swift
.package(url: "https://github.com/tevelee/swift-test-doubles", from: "1.0.0")

// Target dependency
.product(name: "TestDoubles", package: "swift-test-doubles")
```

### ManualStub only (does not build or link Echo)

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

### With Dynamic Replacement (macOS, opt-in)

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    from: "1.0.0",
    traits: ["DynamicReplacement"]
)
```

---

## ManualStub

Write a small conforming struct and delegate to `Stub<Self>`. Works on all platforms; no real conformer needed; no external runtime dependency is built or linked.

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

Zero configuration when a real conformer is linked; module-signature or explicit `Slot`/`MethodDescriptor` setup when none is. RuntimeStub uses a fixed architecture trampoline and fabricated witness tables to intercept protocol calls without compiling code at test startup.

```swift
let stub = RuntimeStub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("Alice")
stub.when { $0.count }.returns(1)

let sut: any UserRepository = stub()
assert(sut.find(id: 99) == "Alice")

stub.verify { $0.find(id: any()) }.wasCalled()
```

Async and async-throwing requirements use a dedicated continuation trampoline:

```swift
let stub = RuntimeStub<any AsyncDataLoader>()

await stub.when { try await $0.load(url: any()) }.returns("data")
await stub.when { await $0.prefetch(urls: any()) }

let sut: any AsyncDataLoader = stub()
assert(try await sut.load(url: "https://example.com") == "data")

await stub.verify { try await $0.load(url: any()) }.wasCalled()
```

```swift
// No real conformer needed when the protocol's Swift module is importable
let stub = try RuntimeStub<any PrototypeCalculator>.makeFromModule()
```

```swift
// Or provide requirement slots directly
let stub = try RuntimeStub<any PrototypeCalculator>.make(
    .method(Int.self, Int.self, returns: Int.self),
    .method(Int.self, returns: String.self),
    .getter(Int.self)
)
```

Explicit slots carry real Swift type names into the trampoline handler, so they
work for high-arity methods, throwing requirements, and indirect struct returns:

```swift
let stub = try RuntimeStub<any Gateway>.make(
    .method(
        args: [Int.self, Money.self, String.self, Bool.self],
        returns: Receipt.self,
        throws: true
    )
)
```

RuntimeStub can also print the explicit setup shape:

```swift
print(try RuntimeStub<any PrototypeCalculator>.setupScaffold())
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

## Dynamic Replacement

When the implementation module is built with Swift's implicit-dynamic frontend flag, TestDoubles can compile and load an `@_dynamicReplacement` image. This reaches concrete declarations that witness-table stubbing cannot: free functions, concrete struct/class methods, final methods, and devirtualized calls.

```swift
// Implementation build setting:
// swiftc -Xfrontend -enable-implicit-dynamic ...

try DynamicReplacementCompiler.loadReplacement(
    moduleName: "MyFeatureReplacements",
    source: """
    import MyFeature

    @_dynamicReplacement(for: fetchUser(id:))
    public func replacement_fetchUser(id: Int) -> User {
        User(id: id, name: "stub")
    }
    """,
    importPaths: [builtProductsDirectory],
    libraryPaths: [builtProductsDirectory],
    linkedLibraries: ["MyFeature"]
)
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

**RuntimeStub: ABI coverage**

`RuntimeStub` uses a fixed architecture trampoline rather than a generated
signature matrix. Arguments and returns are copied with value-witness operations
where metadata is known, including mixed Float/Double arguments, stack-spilled
integer and floating-point arguments, small mixed aggregate arguments, small
direct aggregate returns, throwing errors, and indirect-return buffers. Focused
protocol-level coverage also includes payload enums, optionals, mixed tuples,
concrete metatypes, and opaque existentials. Closure requirements are rejected
at construction because they require compiler-generated witness reabstraction;
use `CompiledStub` or `ManualStub` for those protocols.

**RuntimeStub: async handlers**

Async protocol requirements are supported, including throwing and indirect
returns. `returns` and synchronous `then` closures use the immediate
continuation path. An async `then` closure may suspend while remaining on the
caller's task, inheriting task locals, cancellation, priority, and actor
execution. `thenAsync` remains available as an explicit equivalent. Both
spellings support typed handlers with zero through six arguments, and matcher
specificity is resolved consistently across every response kind.

On x86_64, async requirements with six integer-class arguments currently cross
an unhandled continuation-register boundary. Their typed handler overloads are
available, but invoking that requirement is supported on arm64 only for now.

**CompiledStub is macOS-only**

This package currently gates `CompiledStub` to macOS because it relies on host
compiler invocation, `dlopen`, and build-product discovery in that environment.
Use `ManualStub` or `RuntimeStub` on other platforms.

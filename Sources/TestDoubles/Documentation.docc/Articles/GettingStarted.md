# Getting Started

Learn the core patterns for stubbing, matching, and verifying in your tests.

## Overview

TestDoubles has three strategies — ``ManualStub``, ``RuntimeStub``, and ``CompiledStub`` — but they all share the same stubbing and verification API. This guide covers that shared API using `RuntimeStub` for brevity; everything applies equally to `ManualStub` and `CompiledStub`.

> Note: Pick your strategy first. If you're not sure which one fits, read the ``TestDoubles`` overview page. Once you've chosen, come back here to learn how to use it.

## Stubbing a Method

Register a response with `when(_:)` followed by either `returns(_:)` for a static value or `then(_:)` for dynamic behaviour:

```swift
let stub = RuntimeStub<any UserRepository>()

// Static value
stub.when { $0.find(id: any()) }.returns("Alice")

// Property getter — same syntax
stub.when { $0.count }.returns(1)

let sut: any UserRepository = stub()
sut.find(id: 42)  // → "Alice"
```

`stub()` is a `callAsFunction()` shorthand that produces the protocol existential. Keep the stub alive for the duration of the test — if it's deallocated the mock will fatal-error.

## Matching Arguments

Three matchers cover most cases:

```swift
// Any value of the right type
stub.when { $0.find(id: any()) }.returns("default")

// Exact equality
stub.when { $0.find(id: equal(42)) }.returns("the answer")

// Inline literal — treated as equal() automatically
stub.when { $0.find(id: 99) }.returns("ninety-nine")

// Predicate
stub.when { $0.find(id: any(where: { $0 > 100 })) }.returns("VIP")
```

When a call is dispatched, **the most specific matching stub wins**:

| Matcher | Specificity |
|---------|-------------|
| `equal(_:)` or literal | highest |
| `any(where:)` predicate | middle |
| `any()` | lowest (catch-all) |

Register the catch-all first and the specific cases afterwards — order within the same specificity level doesn't matter:

```swift
stub.when { $0.find(id: any()) }.returns("guest")          // catch-all
stub.when { $0.find(id: any(where: { $0 > 0 })) }.returns("member")
stub.when { $0.find(id: equal(1)) }.returns("admin")       // wins for id == 1
```

## Dynamic Responses with `then`

Use `then` when the return value depends on the arguments, or when the stub should throw:

```swift
// Compute the response from the incoming arguments
stub.when { $0.find(id: any()) }.then { args in
    let id = args[0] as! Int
    return id < 100 ? "User_\(id)" : "VIP_\(id)"
}

// Zero-argument closure for simple cases
stub.when { $0.find(id: any()) }.then { "hardcoded" }

// Throw conditionally
stub.when { try $0.read(path: any()) }.then { args in
    let path = args[0] as! String
    if path.hasPrefix("/private") { throw PermissionError() }
    return "contents of \(path)"
}
```

`then` registers a **throwing stub** — it handles both the error and the success paths in a single closure.

## Trailing Closure Style

For simple stubs, you can collapse `when` and `then` into a single expression:

```swift
// Equivalent to .when { $0.find(id: any()) }.returns("Alice")
stub.when { $0.find(id: any()) } then: { "Alice" }

// With arguments
stub.when { $0.find(id: any()) } then: { args in "User_\(args[0])" }
```

## Verifying Calls

```swift
stub.verify { $0.find(id: any()) }.wasCalled()          // at least once
stub.verify { $0.find(id: any()) }.wasCalled(times: 3)  // exactly 3 times
stub.verify { $0.find(id: any()) }.wasNotCalled()        // never

// Concise forms
stub.verify(called: 2) { $0.find(id: any()) }
stub.verify(never: { $0.reset() })
```

Matchers work in `verify` exactly as in `when` — you can verify specific argument values:

```swift
stub.verify { $0.find(id: equal(42)) }.wasCalled()
stub.verify { $0.save(name: "Alice", age: any()) }.wasCalled()
```

### Inspecting Argument Values

`withArgs` gives you the raw argument lists for all matching calls:

```swift
stub.verify { $0.find(id: any()) }.withArgs { calls in
    // calls: [[Any]] — one [Any] per matching invocation
    assert(calls[0][0] as! Int == 42)
}
```

### Capturing Arguments

``ArgumentCaptor`` records values as calls happen, so you can assert on them after the fact:

```swift
let idCaptor = ArgumentCaptor<Int>()
let sut = stub()
_ = sut.find(id: 7)
_ = sut.find(id: 13)

stub.verify { $0.find(id: idCaptor.capture()) }.wasCalled(times: 2)
assert(idCaptor.values == [7, 13])
```

Captors accumulate across all matching calls; `values` gives them in invocation order.

## Throwing Methods

Use `try` in the `when` closure — the thunk returns zero during recording so the call never actually throws:

```swift
let stub = RuntimeStub<any FileService>()
stub.when { try $0.read(path: any()) }.returns("content")

// Force a throw for specific inputs
stub.when { try $0.read(path: equal("/missing")) }.then { throw FileNotFoundError() }

let sut: any FileService = stub()
try sut.read(path: "/exists")    // → "content"
try sut.read(path: "/missing")  // throws FileNotFoundError
```

Verify throwing methods the same way — wrap in `try` inside the `verify` closure:

```swift
stub.verify { try $0.read(path: any()) }.wasCalled()
```

## Async Methods

Use `await` in the `when` closure and mark the registration site `async`:

```swift
let stub = RuntimeStub<any DataLoader>()

await stub.when { try await $0.fetch(url: any()) }.returns("response")
await stub.when { await $0.prefetch(urls: any()) }  // void async — auto-registered

let sut: any DataLoader = stub()
let result = try await sut.fetch(url: "https://example.com")
```

## Tips and Tricks

### Stub every requirement

RuntimeStub and CompiledStub dispatch every protocol method — including getters. If a test calls a property you haven't stubbed, the thunk returns a zero value silently. Stub everything the SUT will call to make the test intention explicit:

```swift
stub.when { $0.count }.returns(0)       // even if the SUT doesn't use it
stub.when { $0.isAvailable }.returns(true)
```

### Use `any()` as the default, narrow later

Start with `any()` for all arguments, then add specific matchers only when they're load-bearing for the test:

```swift
// First pass — just make it work
stub.when { $0.search(query: any(), limit: any()) }.returns([])

// Second pass — the query matters for this test
stub.when { $0.search(query: equal("alice"), limit: any()) }.returns(["Alice"])
```

### Avoid `stub()` inside `when` closures

Each call to `stub()` allocates a temporary existential container. Call it once and keep the result:

```swift
// Good
let sut: any UserRepository = stub()
_ = sut.find(id: 1)
_ = sut.find(id: 2)

// Wasteful
_ = stub().find(id: 1)
_ = stub().find(id: 2)
```

### Keep the stub alive

The stub must outlive the system under test. In XCTest, declare it as an instance variable. In Swift Testing, keep it in local scope through the whole test function.

```swift
// Works — stub is kept alive for the duration of the function
@Test func myTest() {
    let stub = RuntimeStub<any MyService>()
    stub.when { $0.greet() }.returns("hi")
    let sut = MyController(service: stub())
    sut.doWork()
    stub.verify { $0.greet() }.wasCalled()
}

// Danger — stub may be released before the test completes
@Test func dangerousTest() {
    let sut = MyController(service: RuntimeStub<any MyService>()())
    //                                ^^ temporary — immediately released
}
```

### Diagnose RuntimeStub failures

If `RuntimeStub()` fatal-errors, call `diagnose()` before creating the stub to get a human-readable explanation:

```swift
let d = RuntimeStub<any MyProtocol>.diagnose()
print(d.notes)
// e.g. "No existing conformer was found. Link a concrete type conforming
//       to MyProtocol into your test target."
```

### Custom matchers

Conform to ``ParameterMatcher`` to build reusable domain-specific matchers:

```swift
struct HasPrefix: ParameterMatcher {
    let prefix: String
    func matches(value: Any) -> Bool {
        (value as? String)?.hasPrefix(prefix) == true
    }
}

stub.when { $0.find(name: HasPrefix("A")) }.returns("starts with A")
```

### Verify call order

Use `verifyOrder` to assert that methods were called in a specific sequence:

```swift
stub.verifyOrder {
    $0.load()
    $0.process(data: any())
    $0.save()
}
```

This checks that each call appears *after* the previous one in the call log, without requiring them to be adjacent.

## Next Steps

- <doc:ManualStub> — writing the conforming struct
- <doc:RuntimeStub> — zero-config witness table approach
- <doc:CompiledStub> — compiler-generated conformance for macOS

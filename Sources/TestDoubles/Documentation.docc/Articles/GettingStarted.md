# Getting Started

Learn the core patterns for stubbing, matching, and verifying in your tests.

## Overview

TestDoubles has three strategies — ``ManualStub``, ``RuntimeStub``, and ``CompiledStub``. They share the core `when`, `returns`, matcher, and verification vocabulary, while strategy-specific features such as setters, order verification, and suspending handlers differ. This guide uses `RuntimeStub` for most examples and calls out the exceptions.

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

// Reusable named predicate
let vipID = Matcher<Int>("VIP id") { $0 > 100 }
stub.when { $0.find(id: matching(vipID)) }.returns("VIP")

// Inline named predicate with better failure diagnostics
stub.when { $0.find(id: matching("VIP id") { $0 > 100 }) }.returns("VIP")
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
// Compute the response from typed incoming arguments
stub.when { $0.find(id: any()) }.then { (id: Int) in
    return id < 100 ? "User_\(id)" : "VIP_\(id)"
}

// Multiple arguments are typed too
stub.when { $0.search(query: any(), limit: any()) }.then { (query: String, limit: Int) in
    Array(repeating: query, count: limit)
}

// Zero-argument closure for simple cases
stub.when { $0.find(id: any()) }.then { "hardcoded" }

// Throw conditionally
stub.when { try $0.read(path: any()) }.then { (path: String) throws in
    if path.hasPrefix("/private") { throw PermissionError() }
    return "contents of \(path)"
}
```

Typed `then` overloads cover one through six arguments. The raw `[Any]`
handler is still available when you need a fully dynamic escape hatch:

```swift
stub.when { $0.find(id: any()) }.then { args in
    "User_\(args[0])"
}
```

`then` registers a **throwing stub** — it handles both the error and the success
paths in a single closure.

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

// Typed variant — called once for each matching invocation
stub.verify { $0.save(name: any(), age: any()) }.withArgs { (name: String, age: Int) in
    assert(name.isEmpty == false)
    assert(age > 0)
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
You can also spell capture as a free function when it reads better in argument
position:

```swift
stub.verify { $0.find(id: capture(into: idCaptor)) }.wasCalled(times: 2)
```

## Throwing Methods

Use `try` in the `when` closure. Recording mode returns a typed placeholder without running a configured handler, so the call does not throw:

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

RuntimeStub supports async and async-throwing protocol requirements. Its
`returns` and `then:` responses complete immediately. Use `thenAsync:` when
the configured behavior must await other work or suspend.

```swift
let stub = RuntimeStub<any DataLoader>()

await stub.when { try await $0.fetch(url: any()) }.returns("response")
await stub.when { await $0.prefetch(urls: any()) }  // void async — auto-registered

await stub.when({ try await $0.fetch(url: equal("/slow")) }, thenAsync: {
    try await fixtureServer.response(for: "/slow")
})

let sut: any DataLoader = stub()
let result = try await sut.fetch(url: "https://example.com")

await stub.verify { try await $0.fetch(url: any()) }.wasCalled()
```

Suspending handlers run on the caller's existing task. Task-local values,
cancellation, priority, and actor isolation therefore flow into the handler.

## Tips and Tricks

### Stub every requirement the SUT can call

RuntimeStub and CompiledStub dispatch every protocol method, including getters.
If production code calls a requirement you did not configure, the test fails
with "No stub configured". Stub everything the SUT will call to make the test
intention explicit:

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
// e.g. "No existing conformer was found. Use makeFromModule(), explicit
//       Slot/MethodDescriptor values, or link a conformer for zero-config discovery."
```

### Domain-specific predicates

Use `any(where:)` to build reusable domain-specific predicates:

```swift
func hasPrefix(_ prefix: String) -> String {
    any(where: { value in
        value.hasPrefix(prefix)
    })
}

stub.when { $0.find(name: hasPrefix("A")) }.returns("starts with A")
```

Use ``ParameterMatcher`` only when extending the library itself or adding a
public matcher helper that appends to the matcher context.

```swift
struct NonEmptyMatcher: ParameterMatcher {
    func matches(value: Any) -> Bool {
        (value as? String)?.isEmpty == false
    }
    var specificity: Int { 1 }
}
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

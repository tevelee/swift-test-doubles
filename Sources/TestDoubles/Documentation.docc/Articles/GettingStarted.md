# Getting Started

Arrange protocol behavior, pass the fabricated conformance to the subject under
test, and verify only the interactions that express the test's intent.

## Define a protocol boundary

```swift
protocol UserRepository {
    func find(id: Int) -> String
    func save(name: String, age: Int) throws -> Bool
    var count: Int { get }
}

struct LiveUserRepository: UserRepository {
    // Production implementation.
}
```

The linked `LiveUserRepository` conformance gives TestDoubles the requirement
metadata needed by zero-argument construction.

## Arrange and use a stub

```swift
let stub = try Stub<any UserRepository>()

stub.when { $0.find(id: any()) }.returns("guest")
stub.when { $0.find(id: equal(42)) }.returns("Alice")
stub.when { $0.count }.returns(1)

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "Alice")
```

Use a typed `then` closure when the result depends on arguments:

```swift
stub.when { $0.find(id: any()) }.then { (id: Int) in
    "user-\(id)"
}
```

Throwing behavior uses the same builder:

```swift
stub.when { try $0.save(name: any(), age: any()) }.then {
    (name: String, age: Int) throws in
    guard age >= 0 else { throw ValidationError() }
    return !name.isEmpty
}
```

## Match arguments

- `any()` accepts every value.
- `equal(_:)` uses `Equatable` equality.
- `matching(description:where:)` accepts values satisfying a predicate.
- Literal arguments use best-effort textual comparison; prefer `equal(_:)`
  when equality semantics matter.

The most specific registration wins: explicit equality, literal, predicate,
then wildcard or capture. The first registration wins when specificity ties.

```swift
stub.when { $0.find(id: any()) }.returns("fallback")
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}
    .returns("member")
stub.when { $0.find(id: equal(1)) }.returns("admin")
```

## Verify and capture

Verification defaults to at least one matching call:

```swift
stub.verify { $0.find(id: any()) }
stub.verify(.exactly(2)) { $0.find(id: any()) }
stub.verify(.never) { $0.find(id: equal(-1)) }
```

Capture arguments when the test needs to inspect a side effect:

```swift
let ids = ArgumentCaptor<Int>()
stub.verify(.exactly(2)) { $0.find(id: ids.capture()) }
#expect(ids.values == [1, 42])
```

## Stub async requirements

Async and async-throwing requirements keep the same vocabulary. An async
`then` handler may genuinely suspend as part of the invoking task while
respecting its own actor isolation.

```swift
let stub = try Stub<any DataLoader>()

await stub.when { try await $0.load(url: any()) }.then {
    (url: String) async throws in
    try await fixtureServer.response(for: url)
}

let loader: any DataLoader = stub()
_ = try await loader.load(url: "/users")

await stub.verify { try await $0.load(url: equal("/users")) }
```

## Construct without a linked conformer

Pass typed requirements in declaration order when the test process does not
contain a concrete conformance:

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

Mark throwing and async requirements explicitly:

```swift
let stub = try Stub<any DataLoader>(
    .method(
        URL.self,
        returning: Data.self,
        isThrowing: true,
        isAsync: true
    )
)
```

Construction throws ``StubError`` for an unsupported protocol or requirement
shape. See <doc:StubGuide> for the supported contract and limitations.

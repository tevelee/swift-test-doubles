# Getting Started

Arrange protocol behavior, pass the fabricated conformance to the subject under
test, and verify only the interactions that express the test's intent.

## Define a protocol boundary

Stub the narrow protocol that the subject already depends on:

```swift
protocol UserRepository {
    func find(id: Int) -> String
}

struct LiveUserRepository: UserRepository {
    func find(id: Int) -> String {
        fatalError("Production implementation")
    }
}
```

The linked production conformance gives TestDoubles the requirement metadata
needed by zero-argument construction. It is inspected, not invoked.

## Match and return values

Register a broad fallback first, then add more specific behavior:

```swift
let stub = try Stub<any UserRepository>()
stub.when { $0.find(id: any()) }.returns("guest")
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}.then { (id: Int) in
    "member-\(id)"
}
stub.when { $0.find(id: equal(42)) }.returns("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: -1) == "guest")
#expect(repository.find(id: 7) == "member-7")
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }
stub.verify(.exactly(3)) { $0.find(id: any()) }
stub.verify(.never) { $0.find(id: equal(999)) }
```

`any()` accepts every value, `equal(_:)` uses `Equatable` equality, and
`matching(description:where:)` accepts values satisfying a predicate. Explicit
equality outranks a literal, a literal outranks a predicate, and a predicate
outranks a wildcard or capture. The first registration wins a tie. Verification
defaults to at least one matching call; state a count only when it adds meaning.

## Capture side effects

Capture arguments when a call to a side-effect dependency is the result under
test:

```swift
let stub = try Stub<any NotificationService>()
stub.when { try $0.send(to: any(), message: any()) }

let notifications: any NotificationService = stub()
try notifications.send(to: 1, message: "Welcome")
try notifications.send(to: 2, message: "Try again")

let recipients = ArgumentCaptor<Int>()
let messages = ArgumentCaptor<String>()
stub.verify(.exactly(2)) {
    try $0.send(to: recipients.capture(), message: messages.capture())
}
#expect(recipients.values == [1, 2])
#expect(messages.values == ["Welcome", "Try again"])
```

## Stub async success and failure

Async and async-throwing requirements use the same vocabulary. A typed handler
may genuinely suspend:

```swift
struct LoadError: Error, Equatable {
    let url: String
}

let stub = try Stub<any AsyncDataLoader>()
await stub.when { try await $0.load(url: equal("/users/42")) }.then {
    (url: String) async throws -> String in
    await Task.yield()
    return "profile:\(url)"
}
await stub.when { try await $0.load(url: any()) }.then {
    (url: String) async throws -> String in
    await Task.yield()
    throw LoadError(url: url)
}

let loader: any AsyncDataLoader = stub()
#expect(try await loader.load(url: "/users/42") == "profile:/users/42")
let error = await #expect(throws: LoadError.self) {
    try await loader.load(url: "/missing")
}
#expect(error?.url == "/missing")
```

## Return stateful responses

A handler may model a response sequence when calls are serial:

```swift
let stub = try Stub<any UserRepository>()
var responses = ["syncing", "ready"]
stub.when { $0.find(id: equal(42)) }.then { (_: Int) in
    responses.removeFirst()
}

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "syncing")
#expect(repository.find(id: 42) == "ready")
```

The handler is responsible for synchronizing captured mutable state if calls
may be concurrent.

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
let stub = try Stub<any AsyncDataLoader>(
    .method(
        String.self,
        returning: String.self,
        isThrowing: true,
        isAsync: true
    ),
    .method([String].self, returning: Void.self, isAsync: true),
    .getter(Int.self)
)
```

Construction throws ``StubError`` for an unsupported protocol or requirement
shape. See <doc:StubGuide> for the supported contract and limitations.

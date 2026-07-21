# Getting Started

Arrange protocol behavior, pass the fabricated conformance to the subject under
test, and verify only the interactions that express the test's intent.

## Overview

For the precise support and failure contract behind these examples, see
<doc:StubContract>.

Choose construction based on where TestDoubles can obtain the protocol
requirement signatures:

| Available signature source | Construction |
| --- | --- |
| A concrete conformer is linked into the test process | Use `try Stub<any P>()`. TestDoubles inspects the conformance metadata but never invokes the conformer. |
| The protocol module is built with library evolution and exports resilient requirement symbols | Use `try Stub<any P>()`; no concrete conformer is needed. |
| Neither source is available | Prefer ``Stub/Requirement`` factories using `signatureOf:` protocol members. Use source-less factories only for shapes member references cannot express. |

The first two paths use the same zero-argument initializer. The difference is
only where signature metadata comes from. See <doc:ConstructionGuide> for
safe source-backed requirements, source-less ABI schemas, inheritance order,
and compositions.

### Define a protocol boundary

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

### Match and return values

Register specific behavior first, then a broad fallback:

```swift
let stub = try Stub<any UserRepository>()
stub.when { $0.find(id: equal(42)) }.thenReturn("Alice")
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}.then { (id: Int) in
    "member-\(id)"
}
stub.when { $0.find(id: any()) }.thenReturn("guest")

let repository: any UserRepository = stub()
#expect(repository.find(id: -1) == "guest")
#expect(repository.find(id: 7) == "member-7")
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }
stub.verify(.exactly(3)) { $0.find(id: any()) }
stub.verify(.never()) { $0.find(id: equal(999)) }
```

`any()` accepts every value, `equal(_:)` uses `Equatable` equality, and
`matching(description:where:)` accepts values satisfying a predicate. When
several registrations match a call, the first one wins, like the cases of a
`switch`: register specific matchers first and broad fallbacks last, because
a catch-all registered first swallows everything after it. Verification
defaults to at least one matching call; state a count only when it adds meaning.
A mismatch is reported as a test issue at the `verify` call's source location
and does not terminate the process.

The zero-argument matcher forms synthesize valid recording placeholders for
supported value types. Supply a valid value for references, existentials, and
other types that cannot be synthesized safely:

```swift
let placeholder = ReferenceUser(id: -1, isActive: false)
stub.when { $0.save(user: any(using: placeholder)) }.thenReturn("fallback")
stub.when {
    $0.save(user: matching(using: placeholder, description: "active") {
        $0.isActive
    })
}.thenReturn("active")

let users = ArgumentCaptor<ReferenceUser>()
stub.verify { $0.save(user: users.capture(using: placeholder)) }
```

The supplied value is used only while recording the call. It does not
participate in matching and is not captured.

### Create a one-shot stub value

Use ``makeStub(_:)-7h3si`` when the test only needs a configured protocol value and
does not need to verify its interactions afterward. The surrounding context
determines the protocol existential type:

```swift
let repository: any UserRepository = makeStub {
    $0.when { $0.find(id: any()) }.then { (id: Int) in "user-\(id)" }
}

#expect(repository.find(id: 42) == "user-42")
```

Keep an explicit ``Stub`` when the test needs verification, invocation-log
management, reconfiguration, or access to the generated value more than once.

### Forward behavior through a spy

Use ``Spy`` when a real implementation should handle most calls and the test
needs to observe or replace only selected interactions:

```swift
let spy: Spy<any UserRepository> = makeSpy(forwardingTo: liveRepository)
spy.when { $0.find(id: equal(42)) }.thenReturn("Fixture User")

let repository: any UserRepository = spy()
#expect(repository.find(id: 42) == "Fixture User")
#expect(repository.find(id: 7) == "live-user-7")

spy.verify(.exactly(2)) { $0.find(id: any()) }
```

Matching registrations take precedence; unmatched supported calls forward and
remain verifiable. The forwarding target supplies the requirement signatures.
The factory fails closed with an actionable diagnostic. Use the throwing
``Spy/init(forwardingTo:)`` initializer when construction failure must be
handled by the caller. See <doc:ForwardingSpies> for supported shapes and
construction failures.

### Capture side effects

Capture arguments when a call to a side-effect dependency is the result under
test:

```swift
let stub = try Stub<any NotificationService>()
stub.when { try $0.send(to: any(), message: any()) }.thenDoNothing()

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

When the interaction arrives from another task, wait for a lower-bounded count
without polling:

```swift
await stub.verify(2..., within: .seconds(1)) {
    try $0.send(to: any(), message: any())
}
```

Eventual verification accepts `PartialRangeFrom<Int>` because that expectation
becomes true monotonically as calls arrive. A timeout is reported at the caller
like an immediate count mismatch. After successful verifications,
`verifyNoMoreInteractions()` reports any uncovered calls. Use
`clearRecordedInvocations()` to begin a new interaction window while preserving
configured behavior and behavior-chain state.

To read recorded arguments as typed values, order interactions across several
doubles, flag registrations no call ever used, or reset a double between
parameterized cases, see <doc:InspectingInteractions>.

### Verify relative call order

List only the interactions whose order matters:

```swift
_ = repository.find(id: 1)
_ = repository.find(id: 99)
_ = repository.find(id: 2)

stub.verifyInOrder {
    _ = $0.find(id: equal(1))
    _ = $0.find(id: equal(2))
}
```

`verifyInOrder` searches for a relative subsequence. Unrelated calls may appear
between expectations, and repeated expectations require distinct recorded
calls. The query is non-consuming and does not execute configured handlers. A
successful sequence marks its selected calls for `verifyNoMoreInteractions()`.
Captors commit only when the complete sequence matches. Async ordered
verification uses the post-matcher dispatch order, where matcher captures, call
logging, and behavior reservation are atomic. It is not invocation-entry or
handler-completion order.

### Stub a direct property assignment

Read-write protocol properties support their getter and direct setter:

```swift
let stub = try Stub<any MutableProfile>()
stub.when { $0.displayName = any() }.thenDoNothing()

var profile: any MutableProfile = stub()
profile.displayName = "Blob"

stub.verify { $0.displayName = equal("Blob") }

stub.verifyInOrder(mutating: {
    $0.displayName = equal("Blob")
})
```

Compound assignment and `inout` access use `_modify`. Configure the ordinary
getter and direct setter; `_modify` reads the initial value through the getter,
yields writable storage, and writes the final value back through the setter on
both normal return and thrown unwind:

```swift
stub.when { $0.displayName }.thenReturn("Blob")
stub.when { $0.displayName = any() }.thenDoNothing()

var profile: any MutableProfile = stub()
profile.displayName += "!"

stub.verify { $0.displayName }
stub.verify { $0.displayName = equal("Blob!") }
```

Capture closures should name the ordinary getter or direct setter rather than
perform compound mutation. Use the labeled `verifyInOrder(mutating:)` overload
for an ordered sequence containing assignments, and `verify` for setter counts.

### Stub a protocol subscript

Subscript indices use the same matchers as method arguments. Direct assignment
is recorded in source order even though Swift's setter witness passes the value
before its indices:

```swift
let stub = try Stub<any KeyValueStore>()
stub.when { $0[any()] }.thenReturn(nil)
stub.when { $0[any()] = any() }.thenDoNothing()

var store: any KeyValueStore = stub()
store["theme"] = "dark"

stub.verify { $0[equal("theme")] = equal("dark") }
```

Automatic discovery supports concrete and bounded associated-type subscript
values. Without a linked conformer, use
`Stub.Requirement.subscriptGetter(indexedBy:returning:)` and
`Stub.Requirement.subscriptSetter(indexedBy:assigning:)` in getter-then-setter
order. Compound mutation and `inout` access enter the separate `_modify`
coroutine, which reads through the subscript getter and writes back through the
same indexed setter.

### Bind an unbound associated result

An unbound protocol existential can use caller-supplied concrete metadata when
its associated type appears only in method or getter results:

```swift
let stub = try Stub<any Source>(
    associatedTypes: [
        .binding(
            declaredBy: (any Source).self,
            named: "Element",
            to: Int.self
        )
    ]
)
stub.when { $0.load() }.thenReturn(42)

let loaded = stub().load() as? Int
```

The declaring protocol is part of each binding's identity, which disambiguates
inherited declarations and equal associated-type names across a composition.
Swift exposes an unbound covariant result at its upper bound, so TestDoubles
checks configured values against the supplied concrete metadata. Associated
inputs remain unavailable through an unbound existential; bind the existential
itself, such as `any Source<Int>`, for that full dependent interface.

### Return dynamic Self

A method, getter, or static requirement returning nonoptional `Self` uses
`when(returningSelf:)`. TestDoubles creates a fresh value backed by the same
recorder and runtime graph:

```swift
let stub = try Stub<any Duplicating>()
stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
stub.when { $0.marker() }.thenReturn(42)

let duplicate = stub().duplicate()
#expect(duplicate.marker() == 42)
```

Use `thenThrow` for a fixed error or a `Void`-returning `then` handler when the
requirement has arguments, suspends, or computes an error. TestDoubles creates
the generated value after the handler returns. For explicit construction, write
`.method(returning: .dynamicSelf)`. Optional `Self?` uses
`when(returningOptionalSelf:)`; its builder returns a fresh generated value or
`nil`, and explicit construction uses `.optionalDynamicSelf`. Direct `Self`
inputs remain outside the supported boundary.

### Stub async success and failure

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
await stub.when { try await $0.load(url: any()) }
    .thenThrow(LoadError(url: "/missing"))

let loader: any AsyncDataLoader = stub()
#expect(try await loader.load(url: "/users/42") == "profile:/users/42")
let error = await #expect(throws: LoadError.self) {
    try await loader.load(url: "/missing")
}
#expect(error?.url == "/missing")
```

To control *when* an async call completes rather than only its result, for
loading states, latency, timeouts, and cancellation, see <doc:AsyncBehaviors>.

### Sequence fixed behaviors

Chain fixed returns, errors, and no-ops when consecutive calls should behave
differently:

```swift
let stub = try Stub<any AsyncDataLoader>()
await stub.when { try await $0.load(url: equal("/users/42")) }
    .thenReturn("cached")
    .thenThrow(LoadError(url: "/users/42"))
    .thenReturn("fresh")

let loader: any AsyncDataLoader = stub()
#expect(try await loader.load(url: "/users/42") == "cached")
await #expect(throws: LoadError.self) {
    try await loader.load(url: "/users/42")
}
#expect(try await loader.load(url: "/users/42") == "fresh")
```

Matching calls consume the configured behaviors in order, and the final behavior
repeats. Passing several values to one `thenReturn` remains shorthand for a
return-only chain. Reservation is internally synchronized, and each registration
owns its own chain. Behavior that depends on arguments or richer state belongs
in a `then` handler: synchronous handlers and matcher predicates are `@Sendable`,
async handlers preserve their creation actor or executor, and mutable captures
must be synchronized when calls may be concurrent.

### Choose a construction path

The examples above use automatic discovery from a linked conformance. For
getter-effect hints, explicit requirements, protocol compositions, static
requirements, initializers, typed throws, and metatype lifetime rules, see
<doc:ConstructionGuide>.

If automatic construction reports that no conformer is linked, make a real
conforming value visible as the protocol existential before constructing the
stub. This anchors the conformance metadata that TestDoubles inspects; the
value's requirements are not invoked:

```swift
let conformanceAnchor: any UserRepository = LiveUserRepository()
let stub = try withExtendedLifetime(conformanceAnchor) {
    try Stub<any UserRepository>()
}
```

When the protocol has no real conformer, provide explicit
``Stub/Requirement`` values instead. If construction reports an unsupported
runtime shape, use ``ManualStub`` with a hand-written ``StubConformer``, or
write a hand-written fake. Runtime generation fails closed rather than trying
an ABI shape it cannot safely represent.

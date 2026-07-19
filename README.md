# swift-test-doubles

[![CI](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml/badge.svg)](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/tevelee/swift-test-doubles/branch/main/graph/badge.svg)](https://codecov.io/gh/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Runtime-generated test doubles for Swift protocols. No macros, code generation,
or boilerplate.

## Quick start

```swift
let stub = try Stub<any UserRepository>()

stub.when { $0.find(id: any()) }.thenReturn("guest")
stub.when { $0.find(id: equal(42)) }.thenReturn("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: 42) == "Alice")

stub.verify { $0.find(id: equal(42)) }
```

Choose the construction path based on where TestDoubles can obtain the protocol
requirement signatures:

| Available signature source | Construction |
| --- | --- |
| A concrete conformer is linked into the test process | Use `try Stub<any P>()`. TestDoubles inspects the conformance metadata but never invokes the conformer. |
| The protocol module is built with library evolution and exports resilient requirement symbols | Use `try Stub<any P>()`; no concrete conformer is needed. |
| Neither source is available | Pass explicit `Stub.Requirement` values to `Stub<any P>(...)`, in protocol declaration order. |

See the [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md)
for explicit requirement examples, inheritance order, and protocol compositions.

`Stub` fabricates a protocol conformance and routes witness calls through one
fixed runtime trampoline. The same API covers synchronous, throwing, async, and
async-throwing protocol requirements.

## Why TestDoubles

TestDoubles is for tests that already depend on narrow Swift protocols and want
one small runtime API for matching, typed responses, capture, and verification.
It does not require macros, generated conformers, source generation, or a
compiler invocation while tests run. The tradeoff is an intentionally narrow,
CI-tested ABI boundary: unsupported protocol and requirement shapes fail closed
instead of being approximated.

For a configured value that does not need later verification, use the one-shot
factory:

```swift
let service: any CurrencyService = makeStub {
    $0.when { $0.currency }.then { "EUR" }
}
```

### Forward real behavior with a spy

Use `Spy` when most behavior should stay real and a test needs to observe or
replace only a few interactions:

```swift
let spy: Spy<any UserService> = makeSpy(forwardingTo: liveService)
spy.when { $0.displayName(for: equal("guest")) }
    .thenReturn("Test Guest")

let service: any UserService = spy()
#expect(service.displayName(for: "guest") == "Test Guest") // overridden
#expect(service.displayName(for: "admin") == "Admin")      // forwarded

spy.verify(.exactly(2)) { $0.displayName(for: any()) }
```

A matching `when` registration wins. Every unmatched supported call forwards
to the target and is recorded for verification. The target's conformance also
provides signature discovery, so `Spy` does not need explicit requirements or
a second linked conformer. `makeSpy` fails closed with a construction
diagnostic; use `try Spy<any P>(forwardingTo:)` when the caller needs to handle
construction failure.

Forwarding currently supports instance methods and read-only getters whose
arguments stay within the supported register boundary. Static and
initializer requirements, dynamic `Self` results, function-valued arguments or
results, and `_modify` coroutines fail during construction. Use a hand-written
spy when the protocol needs one of those shapes. See
[Forwarding Spies](Sources/TestDoubles/Documentation.docc/Articles/ForwardingSpies.md).

### Dummy dependencies

Use `makeDummy(_:)` when an API requires a protocol value but the exercised code
path must not invoke it:

```swift
let result = feature.run(analytics: makeDummy(AnalyticsClient.self))
```

The generated value has no behavior, call recording, or verification. Every
protocol invocation fails closed with a diagnostic. Unlike `Stub`, construction
does not inspect argument or result signatures, so function and SIMD values are
safe in the protocol shape as long as the dummy is never used. See
[Dummy Test Doubles](Sources/TestDoubles/Documentation.docc/Articles/DummyTestDoubles.md).

## Installation

Until the first tagged release, depend on the `main` branch explicitly:

```swift
dependencies: [
    .package(
        url: "https://github.com/tevelee/swift-test-doubles",
        branch: "main"
    ),
],
targets: [
    .testTarget(
        name: "MyFeatureTests",
        dependencies: [
            .product(
                name: "TestDoubles",
                package: "swift-test-doubles"
            ),
        ]
    ),
]
```

Once `0.1.0` is tagged, replace `branch: "main"` with `from: "0.1.0"` to use
semantic-versioned releases.

## Runtime support

TestDoubles requires Swift 6.3. The supported runtime matrix is macOS 13+ on
arm64 and x86_64, Linux on arm64 and x86_64, Mac Catalyst 16+ on arm64, and
arm64 simulators for iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+. Physical
iOS, tvOS, visionOS, and watchOS devices are unsupported because the runtime
generates executable trampoline code and CI cannot exercise device execution
policy. `ManualStub` remains available when building for those devices.

For a protocol that conforms to `Sendable`, materialize its value with
`stub(sendability: .unchecked)` or `makeStub(sendability: .unchecked)`. The
explicit form acknowledges that the recorder stores type-erased configuration
and invocation state whose sendability Swift cannot prove. Use it only when the
values, matchers, captors, handlers, and invocation arguments used by the test
are safe for its concurrency pattern.

## Common patterns

The package test suite exercises the public usage patterns shown below. See
[Tests/TestDoublesTests](Tests/TestDoublesTests) for focused examples and
runtime coverage.

### Dynamic responses and matching

Use `thenReturn` for a fixed response, `thenThrow` for a fixed error,
`thenDoNothing` for a no-op, and `then` when behavior depends on the arguments.
More specific registrations win over general fallbacks:

```swift
stub.when { $0.find(id: any()) }.thenReturn("guest")
stub.when {
    $0.find(id: matching(description: "positive", where: { $0 > 0 }))
}.then { (id: Int) in
    "member-\(id)"
}
stub.when { $0.find(id: equal(42)) }.thenReturn("Alice")

let repository: any UserRepository = stub()
#expect(repository.find(id: -1) == "guest")
#expect(repository.find(id: 7) == "member-7")
#expect(repository.find(id: 42) == "Alice")
```

Use `any()` for a wildcard, `equal(_:)` for equality, and `matching` for a
predicate. Explicit equality outranks a literal, a literal outranks a predicate,
and a predicate outranks a wildcard or capture. The first registration wins a
specificity tie. Literal arguments use a best-effort textual comparison; prefer
`equal(_:)` when equality semantics matter.

These forms work directly for most values. Class instances, existentials, and
some other values need one extra recording-only value; see
[Class and existential values](#class-and-existential-values) after the common
examples.

### Async success and failure

Async requirements use the same vocabulary, and handlers may genuinely
suspend:

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

Suspending handlers run as part of the invoking task, preserving task-local
values, cancellation, and priority. An async handler preserves the actor or
executor on which it was formed, including a custom serial executor, and an
actor-isolated caller resumes on its executor after the requirement returns.
Actor-isolate async handlers or synchronize their mutable captures when the
generated existential can be invoked concurrently.

### Capture side effects

Capture arguments when the interaction itself is the result being tested:

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

Immediate verification accepts any `RangeExpression<Int>` and defaults to
`1...` (at least once). Use `.exactly(_)`, `.never()`, `2...`, or `...2` only
when the count adds meaning to the test. When a call arrives from another task,
wait for a monotonic lower bound without polling:

```swift
await stub.verify(2..., within: .seconds(1)) {
    try $0.send(to: any(), message: any())
}
```

A mismatch or timeout is reported through IssueReporting at the `verify`
call's file and line. Successful verification marks its matching calls. Use
`verifyNoMoreInteractions()` to report calls not covered by successful
verification, and `clearRecordedInvocations()` to start a new interaction
window without changing configured behavior or behavior-chain state.

### Ordered interactions

Use `verifyInOrder` when relative order is part of the behavior:

```swift
_ = repository.find(id: 1)
_ = repository.find(id: 99)
_ = repository.find(id: 2)

stub.verifyInOrder {
    _ = $0.find(id: equal(1))
    _ = $0.find(id: equal(2))
}
```

The listed calls form a relative subsequence, so unrelated calls may appear
between them. Repeated expectations require distinct recorded calls. Ordered
verification is non-consuming: it does not change later count verification or
replay configured handlers. A successful sequence marks only its selected calls
for `verifyNoMoreInteractions()`. Captors commit only after the complete ordered
sequence matches. For overlapping calls, recorded order follows the
post-matcher dispatch linearization point: committing matcher captures, logging
the call, and reserving a sequenced behavior happen atomically. It is not
invocation-entry or handler-completion order.

### Direct property setters

Record a direct assignment with the same `when` and `verify` vocabulary:

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

Compound assignment and `&profile.displayName` use Swift's `_modify` coroutine.
Configure the ordinary getter and direct setter; `_modify` obtains the initial
value through the getter, yields writable storage, and writes the final value
back through the setter on both normal return and thrown unwind:

```swift
stub.when { $0.displayName }.thenReturn("Blob")
stub.when { $0.displayName = any() }.thenDoNothing()

var profile: any MutableProfile = stub()
profile.displayName += "!"

stub.verify { $0.displayName }
stub.verify { $0.displayName = equal("Blob!") }
```

Capture closures themselves should still name the ordinary getter or direct
setter, not perform compound mutation. Use the labeled
`verifyInOrder(mutating:)` overload when an ordered sequence contains setter
assignments; `verify` remains the API for asserting their count.

### Protocol subscripts

Configure and verify protocol subscripts with the same matcher syntax as a
method or property. Read-write subscripts preserve Swift's source-level
assignment order even though their setter witness passes the assigned value
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
values. When no conformer is linked, describe the accessor pair explicitly
with `.subscriptGetter(indexedBy:returning:)` and
`.subscriptSetter(indexedBy:assigning:)` in getter-then-setter order. A
read-write subscript's `_modify` witness uses the same getter-then-setter
materialization, preserving the setter's value-first ABI order after indexed
compound mutation.

### Sequenced behaviors

Chain `thenReturn`, `thenThrow`, and `thenDoNothing` when consecutive calls
should behave differently:

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
#expect(try await loader.load(url: "/users/42") == "fresh")
```

Matching calls consume the configured behaviors in order, and the final behavior
repeats. Passing several values to one `thenReturn` remains shorthand for a
return-only chain. Reservation is internally synchronized, and each registration
owns its own chain, so a more specific registration does not advance a general
fallback. Behavior that depends on arguments or richer state belongs in a `then`
handler; synchronous handlers and matcher predicates are `@Sendable`, so
synchronize any mutable captures.

### Class and existential values

<details>
<summary><strong>Why some calls need a recording-only value</strong></summary>

A `when` or `verify` closure runs once immediately so TestDoubles can learn
which protocol requirement it contains. That recording pass still has to make
a valid Swift call: every argument needs a value, and a non-`Void` requirement
has to produce a temporary result.

That temporary value is all “placeholder” means here. It lets the recording
closure execute; it is not an expected argument and it is not the configured
return value.

TestDoubles can create those temporary values for types such as `Int` and
`String`. It cannot safely invent an instance of an arbitrary class or
existential, so you supply any valid instance for the recording pass:

```swift
final class User {
    let id: Int

    init(id: Int) {
        self.id = id
    }
}

protocol UserStore {
    func save(_ user: User)
    func currentUser() -> User
}

let stub = try Stub<any UserStore>()
let recordingUser = User(id: -1) // Used only while `when` and `verify` record.
let alice = User(id: 42)         // The value used by the actual test.

stub.when {
    $0.save(any(using: recordingUser))
}.thenDoNothing()
stub.when(returning: recordingUser) {
    $0.currentUser()
}.thenReturn(alice)

let store: any UserStore = stub()
store.save(alice)
#expect(store.currentUser() === alice)

let savedUsers = ArgumentCaptor<User>()
stub.verify {
    $0.save(savedUsers.capture(using: recordingUser))
}
stub.verify(returning: recordingUser) {
    $0.currentUser()
}

#expect(savedUsers.values.first === alice)
```

The important distinction is:

- `any(using: recordingUser)` still matches any `User`; it does not match only
  `recordingUser`.
- `returning: recordingUser` supplies the temporary result of the recording
  pass; `.thenReturn(alice)` controls what production code receives.
- `capture(using: recordingUser)` captures the real argument passed later—in
  this example, `alice`.

The recording-only value never becomes configured behavior unless you also
pass it to `thenReturn` or return it from a `then` handler. The same rule applies
to the async overloads and to optional `nil` placeholders.

</details>

## Construction

The zero-argument initializer discovers requirement signatures from real
conformers linked into the test process or from exported per-requirement method
descriptor symbols on protocols compiled with library evolution. The latter
needs no concrete implementation: the protocol metatype leads to its ABI
requirement records, and the exact descriptor symbols carry the signatures.
Inherited protocols and compositions are supported; every declaring protocol
must provide one of these runtime sources.
Ordinary class-constrained Swift protocols use the same construction API. On
Apple platforms, an ordinary existential may also combine Swift protocols with
an `NSObject`-backed superclass:

```swift
let stub = try Stub<any UserRepository>()
let combined = try Stub<any UserRepository & NotificationService>()
let classOnly = try Stub<any ClassOnlyRepository>()
let objectBacked = try Stub<any NSObject & LifecycleReporting>(
    .method(returning: Int.self)
)
```

Class existentials retain the generated payload directly, so values produced
by `stub()` remain valid after the `Stub` instance is released. Repeated calls
reuse that payload. The conformance is intentionally not registered
process-wide. Keep the protocol existential: erasing it to `AnyObject` discards
the fabricated witness tables, and dynamically casting it back is unsupported
and may trap under optimization. For a superclass constraint, construction
creates a genuine superclass instance through `init()` and attaches the stub's
runtime resources to it. This supports imported Objective-C classes and
Swift-defined `NSObject` subclasses whose default initializer is usable; real
superclass members keep their normal implementation. Native Swift-only
superclasses, Objective-C-only protocols, and special runtime protocols remain
rejected.

### Static and initializer requirements

Instance and static requirements share `when` and `verify`. Swift cannot spell
the opened existential metatype as the closure parameter, so invoke a static
requirement through `type(of:)`:

```swift
stub.when { type(of: $0).defaultName() }.thenReturn("Guest")

let value: any UserFactory = stub()
#expect(type(of: value).defaultName() == "Guest")
```

Record initializers through the labeled `when(initializer:)` overload.
They return another generated value backed by the same recorder and runtime
graph. Finish a nonfailable initializer with `thenInitialize()`; failable
initializers can instead return `nil`:

```swift
stub.when(initializer: {
    type(of: $0).init(id: any())
}).thenInitialize()

stub.when(initializer: {
    type(of: $0).init(validating: any())
}).then { id in
    id > 0 ? .initialize : .returnNil
}
```

Initializer handlers may be synchronous or async and may throw when the
requirement throws; use `thenThrow` for a fixed error. Use `withValue` when
passing a generated metatype into code
under test; it keeps the witness tables and executable trampolines alive for the
operation:

```swift
try await stub.withValue { value in
    try await service.run(factory: type(of: value))
}
```

The metatype must not escape the `withValue` operation. Unlike a generated
protocol value, a Swift metatype has no ownership hook with which to retain the
stub's runtime allocations.

### Dynamic Self results

A method, getter, or static requirement that returns nonoptional `Self` can
produce a fresh value backed by the same recorder and runtime graph:

```swift
let stub = try Stub<any Duplicating>()
stub.when(returningSelf: { $0.duplicate() }).thenReturnValue()
stub.when { $0.marker() }.thenReturn(42)

let duplicate = stub().duplicate()
#expect(duplicate.marker() == 42)
```

Use `thenThrow` for a fixed error or a `Void`-returning `then` handler when
arguments, suspension, or a computed throwing failure matter. TestDoubles
creates the generated result only after the handler returns. This prevents a
value from a different fabricated witness graph from being returned
accidentally. Without a linked conformer, describe the result as
`.method(returning: .dynamicSelf)`. Optional dynamic `Self?` uses
`when(returningOptionalSelf:)`, whose builder can return a fresh value or
`nil`; describe an explicit result as `.optionalDynamicSelf`. Direct `Self`
inputs remain unsupported.

### Function and closure values

Automatic runtime stubs can directly accept and return concrete native Swift
closures without requirement chunks, protocol annotations, or access to the
protocol source when the complete function shape lies inside the documented
automatic boundary:

```swift
typealias Transform = @Sendable (Int) -> Int
let identity: Transform = { $0 }
let stub = try Stub<any Transformer>()
stub.when(returning: identity) {
    $0.transform(any(using: identity))
}.then { transform in
    let captured = transform(20) + 1
    return { _ in captured }
}
```

Use valid placeholders for function arguments and recording results as shown;
they are needed only while `when` or `verify` captures the invocation. See
[Function Values](Sources/TestDoubles/Documentation.docc/Articles/FunctionValues.md)
for the canonical support matrix, exact register limits, function-valued
getters, handler ergonomics, explicit compiler adapter, and fail-closed
boundary.

### Bound primary associated types

A bounded associated-type slice supports one or more concretely bound primary
associated types across the complete protocol layout. Declaring protocols may
be value- or class-constrained, inherited as bases, and composed with other
associated-type or ordinary protocols. Direct occurrences, plus `Element?`,
`[Element]`, and `Set<Element>`, may be used by methods and getters with any
combination of `async` and untyped `throws`; effectful getters must be described
explicitly. Direct dependent setters, initializer arguments, and consuming
direct, optional, array, and set arguments are also supported:

```swift
protocol Source<Element> {
    associatedtype Element: Equatable
    func load() -> Element
    func transform(_ value: Element) -> Element
}

let stub = try Stub<any Source<Int>>()
stub.when { $0.load() }.thenReturn(41)
stub.when { $0.transform(any()) }.then { $0 + 1 }
```

When the existential itself is unbound, caller-supplied bindings support the
covariant part of the protocol instead. Name both the declaring protocol and
associated type so inheritance and compositions stay unambiguous:

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
stub.when { $0.load() }.thenReturn(41)

let value = stub().load() as? Int
```

Swift erases the unbound result to its upper bound (`Any` when unconstrained),
so fixed results are checked against the supplied concrete metadata at
registration and handler results are checked at invocation. Caller-bound
associated inputs remain unsupported because Swift cannot invoke those members
through an unbound existential. Use `Stub<any Source<Int>>` when the protocol
needs dependent inputs, setters, or statically typed results.

Explicit requirements must distinguish a dependent `Element` value from an
ordinary concrete `Int`, because their witness calling conventions differ:

```swift
typealias SourceStub = Stub<any Source<Int>>
let element = SourceStub.Requirement.Value.associatedType(named: "Element")
let optionalElement = SourceStub.Requirement.Value
    .optionalAssociatedType(named: "Element")
let elements = SourceStub.Requirement.Value
    .arrayOfAssociatedType(named: "Element")
let elementSet = SourceStub.Requirement.Value
    .setOfAssociatedType(named: "Element")
let consumedElements = elements.consuming()

let stub = try SourceStub(
    .method(returning: element),
    .method(element, returning: element)
)
```

See the [associated-type ABI notes](Sources/TestDoubles/Documentation.docc/Articles/BoundAssociatedTypes.md)
for the exact supported and rejected shapes.

## Getter effect hints

Most protocols do not need this initializer. Keep using `try Stub<any P>()`
when the protocol has no property getters, or when all of its getters are
synchronous and nonthrowing.

Use `getterEffects:` when a getter is `async` or `throws`. Swift's runtime
metadata tells TestDoubles the getter's result type and whether it is `async`,
but not whether it can throw. Each hint supplies only that missing answer:

- `.nonthrowing` means the getter does not throw, whether it is synchronous or
  async.
- `.throwing` means the getter uses ordinary untyped `throws`, whether it is
  synchronous or async.

That is why even a nonthrowing `get async` property needs `.nonthrowing`:
TestDoubles can see `async`, but refuses to guess the missing throwing behavior.

For example, the protocol has two getters, so construction receives two hints
in the same order:

```swift
protocol CachedProfile {
    var cachedName: String { get }
    var freshName: String { get async throws }
}

let stub = try Stub<any CachedProfile>(
    getterEffects: .nonthrowing, // cachedName
    .throwing                    // freshName
)

stub.when { $0.cachedName }.thenReturn("Cached")
await stub.when { try await $0.freshName }.thenReturn("Fresh")
```

The hints do not configure either property. They only let TestDoubles construct
the correct calling convention; `when` still configures the values as usual.

<details>
<summary><strong>Exact ordering, inheritance, and composition rules</strong></summary>

Once you use `getterEffects:`, supply one hint for every getter. Methods,
initializers, and setters do not consume a hint. For one protocol with
inheritance, order the hints base-first and then in declaration order.

For a protocol composition, group the hints by the protocol that declares each
getter. This avoids one ambiguous flat list:

```swift
protocol CachedProfile {
    var cachedName: String { get }
}

protocol NetworkProfile {
    var freshName: String { get async throws }
}

let stub = try Stub<any CachedProfile & NetworkProfile>(
    getterEffectsByProtocol: .effects(
        declaredBy: CachedProfile.self,
        .nonthrowing
    ),
    .effects(
        declaredBy: NetworkProfile.self,
        .throwing
    )
)
```

Group order does not matter. Within each group, follow that protocol's getter
declaration order. Inherited getters belong to the protocol that originally
declares them.

Hints classify only ordinary untyped `throws`; they cannot name a typed error.
Typed-throwing getters are outside `Stub`'s runtime boundary; use `ManualStub`
or a hand-written fake for those. When no automatic signature source is
available, describe supported ordinary getters with explicit requirements. See
the [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md)
for those forms.

</details>

## Explicit requirements

If no conformer is linked and resilient requirement symbols are unavailable,
describe the requirements with Swift types. For one root protocol, use a flat
base-first, depth-first order: each inherited protocol appears at its first
occurrence, followed by the requirements declared by the root. A shared diamond
base appears once.

```swift
let stub = try Stub<any PrototypeCalculator>(
    .method(Int.self, Int.self, returning: Int.self),
    .method(Int.self, returning: String.self),
    .getter(Int.self)
)
```

Read-write properties contribute their getter followed by their setter:

```swift
let profile = try Stub<any MutableProfile>(
    .getter(String.self),
    .setter(String.self)
)
```

Describe an initializer with its argument types and effects; its `Self` result
is implicit:

```swift
let factory = try Stub<any PrototypeFactory>(
    .initializer(Int.self, isThrowing: true),
    .method(returning: String.self)
)
```

For a composition, group requirements by the bare protocol that originally
declares them. Group order is irrelevant; order inside each group follows that
protocol's declaration. Supply a shared inherited protocol once:

```swift
let store = try Stub<any ExplicitReader & ExplicitWriter>(
    requirementsByProtocol: .requirements(
        declaredBy: ExplicitWriter.self,
        .method(Int.self, String.self, returning: Void.self)
    ),
    .requirements(
        declaredBy: ExplicitReader.self,
        .method(Int.self, returning: String.self)
    )
)
```

Effects are part of an explicit requirement:

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

Name a typed error with `throwing:`. Add `isAsync: true` for an async method.
This also works when no real conformer is linked:

```swift
let stub = try Stub<any AsyncTypedDataLoader>(
    .method(
        String.self,
        returning: Data.self,
        throwing: LoadError.self,
        isAsync: true
    )
)
```

Construction throws `StubError` when the protocol or a requirement shape cannot
be supported. Automatic discovery resolves concrete runtime metadata for every
argument and result before allocating a witness table. When a linked
conformance is available, it also validates every signature component that can
be discovered reliably. Getter throwing behavior remains caller-supplied. No
construction path launches external tools.

## Supported features

- Instance and static methods, ordinary getters, direct property setters, and
  protocol subscript getters and setters on ordinary opaque and
  class-constrained Swift protocol existentials.
- Ordinary superclass-constrained existentials on Apple platforms when the
  superclass inherits `NSObject` and has a usable default initializer. Swift
  protocol requirements may be inherited or composed; concrete superclass
  members execute normally on the genuine base instance.
- Nonfailable and failable initializer requirements, including throwing and
  async variants. Successful initialization creates a new payload backed by the
  same recorder and runtime graph.
- Direct and optional dynamic `Self` results from methods, getters, and static
  requirements, with specialized fresh-value, optional-nil, and typed-handler
  configuration.
- Protocol inheritance, including shared diamond bases, and multi-protocol
  compositions.
- One or more concretely bound primary associated types across an opaque or
  class-constrained protocol layout, including declarations on inherited
  bases, directly alongside inherited protocols, and across composed roots.
  Direct dependent arguments and results, dependent setters and initializer
  arguments, and dependent `Optional`, `Array`, and `Set` values are supported
  with any combination of `async` and untyped `throws` where applicable.
  Direct and supported-container method arguments may be consuming.
- Caller-supplied concrete bindings for unbound associated types used only in
  covariant method or getter results. Binding identity includes the declaring
  protocol so inherited declarations and repeated names in compositions stay
  distinct.
- Synchronous, throwing, async, and async-throwing methods, plus ordinary
  getters and explicitly described effectful getters.
- Function arguments and results across the automatic and explicit-adapter
  slices documented in
  [Function Values](Sources/TestDoubles/Documentation.docc/Articles/FunctionValues.md).
- Automatically discovered or explicitly described typed-throwing methods
  with a concrete error type across otherwise supported concrete and associated
  result layouts, including async suspension and caller-provided indirect
  success and error storage.
- Fixed returns and errors, mixed behavior chains for consecutive calls, and
  typed handlers of arbitrary arity.
- Genuinely suspending async handlers.
- Equality, predicate, wildcard, and capture matchers.
- Immediate and event-driven lower-bound verification, relative-order
  verification, clearing recorded invocations, and reporting interactions not
  covered by successful verification.
- Compound assignment and `inout` mutation through `_modify`, materialized by
  an ordinary getter and written back through its paired setter on normal and
  unwind paths.
- Concurrent invocation after serial stub configuration when configured values,
  matcher and captor state, and captures are safe to share.
- Conditional `Sendable` conformance for `ArgumentCaptor<T>` when `T` is
  `Sendable`.
- Integer, floating-point, direct aggregate, indirect, void, existential,
  optional, enum, tuple, metatype, and string values covered by ABI tests.
- Explicit recording-result placeholders for reference, existential, optional,
  and other values that cannot be synthesized safely.

Enums, tuples, strings, and optionals do not need dedicated public APIs. Their
support depends on their ABI representation and the runtime metadata available
to the trampoline.

## Limitations

- Function-value support follows the canonical automatic and explicit-adapter
  matrix in
  [Function Values](Sources/TestDoubles/Documentation.docc/Articles/FunctionValues.md).
  Shapes outside that boundary fail closed during construction. Typed-throwing
  closure values require macOS 15, iOS 18, Mac Catalyst 18, tvOS 18, or
  visionOS 2; this does not raise the package's deployment target for other
  function values or typed-throwing protocol methods.
- Typed throws is limited to methods with a concrete error type, discovered
  automatically or named by an explicit `throwing:` requirement. Synchronous
  and async methods are supported; error types that themselves depend on an
  associated type remain rejected. An invoked typed-throwing method must have a
  matching registration whose handler throws only its declared error type;
  framework configuration errors cannot be transported through that restricted
  error channel. Ordinary untyped `throws` remains supported across the broader
  documented boundary.
- Associated-type protocols outside the bounded slice remain unsupported,
  including unbound associated types without complete caller bindings,
  caller-bound associated inputs, nested dependent values other than
  `Optional`, `Array`, and `Set`, broader same-type constraints,
  `AnyObject`-constrained associated types, and typed errors that themselves
  depend on an associated type.
- Superclass-constrained existentials remain unsupported for native Swift-only
  base classes, bound-associated-type extended existentials, initializer
  requirements, and dynamic `Self` results. Objective-C-only protocol
  existentials and `_read` requirements also remain unsupported.
- Direct `Self` arguments remain unsupported.
- A generated protocol value retains the stub runtime, but an extracted
  metatype does not. Keep the `Stub` or a generated value alive, preferably with
  `withValue`, for the complete static or initializer invocation.
- Automatic discovery cannot determine whether a getter throws. Supply a
  complete `getterEffects:` hint list to retain automatic signature discovery,
  or describe the requirements explicitly. Async getters without either source
  of truth are rejected so their effects cannot be silently misclassified.
- Explicit requirement types, order, and effects must exactly match the
  declaration. Flat inherited requirements are base-first, depth-first, and
  first-seen; compositions require one group per directly declaring protocol.
  Linked conformance symbols and resilient per-requirement descriptor symbols
  are used to check every reliably discoverable component. Without either
  symbol source and concrete type metadata, Swift protocol metadata exposes
  only requirement count and kind; getter throwing behavior is never
  discoverable and remains caller-supplied.
- `any()`, `matching`, and `ArgumentCaptor.capture()` cannot synthesize every
  reference or existential value. Pass a valid value to the corresponding
  `using:` overload; it is used only to record the invocation.
- Construction rejects async requirements whose witness receiver, arguments,
  and hidden result or error storage consume all available general-purpose
  argument registers: six on x86_64 and eight on arm64. Keeping one register
  free prevents the trampoline from crossing an unsupported continuation
  boundary.
- Concrete/final methods and devirtualized calls are not protocol witness calls
  and are outside the library's scope.
- Configure and verify a stub serially and keep the `Stub` itself on one
  isolation domain. A generated value whose protocol is `Sendable` may cross
  concurrency domains only when configured fixed and sequenced behavior
  payloads, matcher and captor state, and handler captures are themselves safe
  to share.
  Synchronous handlers and predicates satisfy `@Sendable`; async handlers must
  be actor-isolated or protect mutable captures. Keep the `Stub`, its recording
  builders, and verification operations on one isolation domain. A
  `StubBehaviorChain` is conditionally `Sendable` when its result is, but finish
  configuring it before matching invocations begin.

The generated existential and every successful initializer result own their
payload, witness table, trampolines, and recorder. They remain valid if the
original `Stub` instance is released.

## Manual stubbing

When a protocol can't be stubbed by `Stub<P>` because its requirement shape is
outside the runtime ABI boundary or the runtime trampoline doesn't run on its
platform, write a small conforming struct by hand and get the same
`when`/`then`/`thenReturn`/`thenThrow`/`verify`/`verifyInOrder` ergonomics:

```swift
struct MyServiceStub: MyService, StubConformer {
    let stub: ManualStub<Self>

    func fetch(id: Int) -> String { stub.fetch(id: id) }
    func reset() { stub.reset() }
}

let stub = ManualStub<MyServiceStub>()
stub.when { $0.fetch(id: equal(42)) }.thenReturn("Alice")

let service: any MyService = stub()
#expect(service.fetch(id: 42) == "Alice")

stub.verify { $0.fetch(id: equal(42)) }
```

See [Manual Stub](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md)
for the full route reference (throwing methods and getters route through
`.throwing`; async property getters need an explicit fallback method) and
tradeoffs.

## Architecture and further documentation

- [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
- [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md)
- [Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md)
- [Manual Stub](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md)
- [Bound Associated Types](Sources/TestDoubles/Documentation.docc/Articles/BoundAssociatedTypes.md)
- [Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes, [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
standards, [SECURITY.md](SECURITY.md) for private vulnerability reporting, and
[CHANGELOG.md](CHANGELOG.md) for release changes.

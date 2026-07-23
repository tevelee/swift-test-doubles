# swift-test-doubles

[![CI](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml/badge.svg)](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/tevelee/swift-test-doubles/branch/main/graph/badge.svg)](https://codecov.io/gh/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Mocks for Swift protocols, created at runtime.** No macros, no code
generation, no hand-written mock classes. Point `Stub` at a protocol and get a
real, configurable, verifiable implementation back while your test is running.

## Quick start

```swift
import TestDoubles

protocol AuthService {
    func signIn(user: String, password: String) async throws -> String
}

enum AuthError: Error { case invalidCredentials }
```

```swift
let auth = try Stub<any AuthService>()

await auth.when { try await $0.signIn(user: equal("blob"), password: equal("sekret")) }
    .thenReturn("session-42")
await auth.when { try await $0.signIn(user: any(), password: any()) }
    .thenThrow(AuthError.invalidCredentials)

// A real `any AuthService`, ready to hand to the code under test.
let service: any AuthService = auth()

#expect(try await service.signIn(user: "blob", password: "sekret") == "session-42")
await #expect(throws: AuthError.self) {
    try await service.signIn(user: "blob", password: "hunter2")
}

await auth.verify(.exactly(2)) { try await $0.signIn(user: any(), password: any()) }
```

There is no `MockAuthService` in this test. Nobody wrote one, no build tool
generated one, and no macro expanded one. `Stub` built a genuine
`AuthService` conformance at runtime and returned it as an ordinary
existential. Sync, throwing, async, and async-throwing requirements all use
the same vocabulary: `when`, `thenReturn`, `verify`.

The only thing `Stub` needs is a source for the protocol's signatures. In
most projects that is your production conformance, which is inspected but
never invoked. See [how construction finds your protocol's
signatures](#the-fine-print) for the other paths.

## Why runtime doubles?

Every mocking approach in Swift pays for protocol conformance somewhere.
Hand-written mocks take maintenance every time a protocol changes, code
generation needs build tooling and generated files that have to stay in sync,
and macros add compile time and only help with protocols you can annotate.

TestDoubles pays that cost once, inside the library. At test time it reads
the Swift runtime's own metadata to learn a protocol's requirements,
fabricates a real witness table for it, and routes every call through a
hand-written assembly trampoline that reconstructs typed arguments exactly as
the Swift calling convention laid them out. This works for methods,
properties, subscripts, initializers, and static requirements, with no
per-protocol setup of any kind.

The tradeoff: the supported protocol surface is an explicit, CI-tested ABI
boundary. A shape outside it fails at construction with a precise diagnostic
instead of an approximation that silently misbehaves. The boundary is wide
(see [the fine print](#the-fine-print)), and `ManualStub` covers what's
beyond it with the same API.

## What you can do

### Shape responses per argument

Matchers pick the response. More specific registrations win over general
fallbacks, so you can set a default and override only the cases the test
cares about.

```swift
protocol FeatureFlags {
    func isEnabled(_ flag: String, for userID: Int) -> Bool
}
```

```swift
let flags = try Stub<any FeatureFlags>()

flags.when { $0.isEnabled(equal("new_checkout"), for: equal(7)) }.thenReturn(true)
flags.when { $0.isEnabled(equal("new_checkout"), for: any()) }
    .then { (_: String, userID: Int) in userID.isMultiple(of: 2) }
flags.when { $0.isEnabled(any(), for: any()) }.thenReturn(false)

let sut: any FeatureFlags = flags()
#expect(sut.isEnabled("dark_mode", for: 1) == false)   // fallback
#expect(sut.isEnabled("new_checkout", for: 4) == true) // computed
#expect(sut.isEnabled("new_checkout", for: 7) == true) // pinned
```

`any()` matches everything, `matching(description:where:)` matches a
predicate, `equal(_:)` matches a value, and `then` computes the answer from
the actual arguments. When several registrations match a call, the first one
wins, like the cases of a `switch`: register specific matchers first and
broad fallbacks last, because a catch-all registered first swallows
everything after it.

There is a richer vocabulary for common cases. `notEqual(_:)` and
`identical(to:)` refine equality; `greaterThan`, `atLeast`, `lessThan`,
`atMost`, and `inRange(_:)` match `Comparable` arguments; `isNil()`,
`notNil()`, and `some(matcher)` match optionals; `isEmpty()`, `nonEmpty()`,
`hasCount`, `contains`, `containsAll`, `startsWith`, and `endsWith` match
collections; `hasPrefix`, `hasSuffix`, `containsSubstring`,
`equalsIgnoringCase`, and `matchesRegex` match strings; and `not`, `allOf`,
`anyOf`, and `oneOf` compose matchers with boolean logic. Composition stays
positional, so `allOf(events.capture(), hasPrefix("purchase"))` captures only
the arguments that satisfy the whole expression. Use matcher functions for
every argument of a registration or none — a call cannot mix bare literals and
matchers.

### Simulate failure and recovery

Chain behaviors for consecutive calls to simulate conditions you could never
reproduce against a real dependency, like a network that fails twice and then
recovers.

```swift
protocol FeedLoader {
    func loadFeed() async throws -> [String]
}
```

```swift
let loader = try Stub<any FeedLoader>()

await loader.when { try await $0.loadFeed() }
    .thenThrow(URLError(.timedOut))
    .thenThrow(URLError(.networkConnectionLost))
    .thenReturn(["Hello, world"])

let feed = FeedViewModel(loader: loader())
await feed.refresh()

#expect(feed.posts == ["Hello, world"])
#expect(feed.retryCount == 2)
```

Each matching call consumes the next behavior in the chain, and the last one
repeats for every call after that. Each registration owns its own chain, so a
call that matches a more specific registration does not advance a general
fallback's chain. Retry logic like this is hard to test any other way.

When the response depends on *which* attempt this is rather than a fixed list,
`thenForEachCall` hands the computed handler a running call count as its first
argument, ahead of the requirement's typed arguments:

```swift
loader.when { try await $0.loadFeed() }.thenForEachCall { attempt in
    if attempt < 3 { throw URLError(.timedOut) }
    return ["Hello, world"]
}
```

The count starts at 1 and increments once per matching call, scoped to this
registration just like a behavior chain. Trailing arguments may be omitted, so
a handler can take the count alone or the count followed by a leading prefix of
the requirement's arguments.

### Control async timing

Testing async code often means asserting what happens *while* a call is in
flight, not just what it returns. Configure the timing of a completion with the
same vocabulary, no `Task.sleep` required.

```swift
let loader = try Stub<any FeedLoader>()
let suspension = await loader.when { try await $0.loadFeed() }.thenSuspend()

let feed = FeedViewModel(loader: loader())
let refresh = Task { await feed.refresh() }

await suspension.waitForCall()   // the call has arrived and parked
#expect(feed.isLoading)

suspension.resume(returning: ["Hello, world"])
await refresh.value
#expect(feed.isLoading == false)
```

`thenSuspend()` hands the test a handle that completes parked calls on demand,
in arrival order. Alongside it, `thenReturn(_:after:)` delivers a result after a
delay, `thenNeverReturn()` models a wedged dependency for timeout paths, and
`thenAwaitCancellation()` completes when the calling task is cancelled. All four
need an async requirement and fail closed on a synchronous one. See
[Async Behaviors](Sources/TestDoubles/Documentation.docc/Articles/AsyncBehaviors.md)
for the full contract.

### Verify what happened

When the interaction is the outcome, as with analytics, persistence, or
notifications, verify calls, counts, arguments, and order.

```swift
protocol Analytics {
    func track(event: String, value: Int)
}
```

```swift
let analytics = try Stub<any Analytics>()
analytics.when { $0.track(event: any(), value: any()) }.thenDoNothing()

let checkout = Checkout(analytics: analytics())
checkout.add(item: "socks", price: 30)
checkout.add(item: "hat", price: 12)
checkout.placeOrder()

analytics.verify { $0.track(event: equal("purchase"), value: equal(42)) }
analytics.verify(.never()) { $0.track(event: equal("error"), value: any()) }

let events = ArgumentCaptor<String>()
analytics.verify(.exactly(3)) { $0.track(event: events.capture(), value: any()) }
#expect(events.values == ["add_to_cart", "add_to_cart", "purchase"])

analytics.verifyInOrder {
    $0.track(event: equal("add_to_cart"), value: any())
    $0.track(event: equal("purchase"), value: any())
}
```

When the call happens on another task, wait for it instead of sleeping:

```swift
await analytics.verify(1..., within: .seconds(1)) {
    $0.track(event: equal("sync_completed"), value: any())
}
```

`verify` defaults to "at least once"; pass a count such as `.exactly(2)`,
`.never()`, or a range like `...2` only when the number itself matters.
`verifyInOrder` checks a relative subsequence, so unrelated calls may appear
between the listed ones. Verification never consumes configured behavior, and
failures are reported as test issues at the `verify` call's own file and
line. There is also `verifyNoMoreInteractions()` to catch calls no successful
verification has covered.

For custom assertions, read recorded arguments as typed tuples with
`invocations`; `describeInteractions()` dumps the whole call log as a
human-readable, ordered string when a failing `verify` leaves you asking what
actually got called; `InvocationOrder` checks call order across several doubles
at once; `verifyNoUnusedStubs()` flags registrations no call matched; and
`reset()` restores a double between parameterized cases. See
[Inspecting Interactions](Sources/TestDoubles/Documentation.docc/Articles/InspectingInteractions.md).

```swift
let events: [(String, Int)] = analytics.invocations {
    $0.track(event: any(), value: any())
}
#expect(events == [("add_to_cart", 30), ("add_to_cart", 12), ("purchase", 42)])
```

### Spy: keep the real thing, override one call

`Spy` forwards to a real implementation, records everything, and lets you
replace only the interactions the test needs to control.

```swift
protocol Translator {
    func translate(_ key: String) -> String
}

struct LiveTranslator: Translator {
    func translate(_ key: String) -> String { NSLocalizedString(key, comment: "") }
}
```

```swift
let spy: Spy<any Translator> = Spy.make(forwardingTo: LiveTranslator())
spy.when { $0.translate(equal("greeting.new_user")) }.thenReturn("Howdy, partner")

let translator: any Translator = spy()
#expect(translator.translate("greeting.new_user") == "Howdy, partner") // overridden
#expect(translator.translate("farewell.title") == "Goodbye")           // forwarded

spy.verify(.exactly(2)) { $0.translate(any()) }
```

A matching `when` registration wins, and the first matching one is used,
just as with `Stub`. Every other supported call forwards to the target and
is recorded, so verification covers overridden and forwarded calls alike. The target's conformance also supplies the signature metadata,
so a spy needs no other discovery source. A registration can also hand a call
back to the real implementation explicitly with `thenForward()`, which lets a
chain fail a few times and then forward for real.

### Dummy: dependencies that must never be touched

When an initializer demands a dependency the exercised code path must not
use, pass a dummy. Any call on it fails the test with a diagnostic naming the
requirement, which is a stronger guarantee than a silent no-op mock.

```swift
let checkout = Checkout(
    gateway: gateway(),
    analytics: Dummy.make() // this path must never track anything
)
```

### One-shot stubs

When a test only needs a configured value and no verification afterward,
there is a shorthand:

```swift
let translator: any Translator = Stub.make {
    $0.when { $0.translate(any()) }.then { (key: String) in "«\(key)»" }
}
```

Keep an explicit `Stub` when the test needs verification, reconfiguration, or
the generated value more than once.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/tevelee/swift-test-doubles",
        .upToNextMinor(from: "0.0.1")
    ),
],
targets: [
    .testTarget(
        name: "MyFeatureTests",
        dependencies: [
            .product(name: "TestDoubles", package: "swift-test-doubles"),
        ]
    ),
]
```

## The fine print

<details>
<summary><strong>Requirements and platforms</strong></summary>

TestDoubles requires Swift 6.3. The CI-executed runtime matrix is macOS 13+ on
arm64 and x86_64, Linux on arm64 and x86_64, Mac Catalyst 16+ on arm64, and
arm64 simulators for iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+. Android
arm64 and x86_64 are provisional cross-build targets, and wasm32-unknown-wasip1
is a `ManualStub`-only target.

Android support is cross-build validated in CI for debug and release test
targets with the official Swift 6.3.3 Android SDK and NDK r27d or later. The
dependency graph must resolve Echo 0.0.6 or newer for Android ELF image
discovery; this repository pins 0.0.6. CI does not currently execute the tests
on an Android emulator or device, so Android is not yet runtime-validated.

Physical iOS, tvOS, visionOS, and watchOS devices are unsupported because the
runtime generates executable trampoline code and CI cannot exercise device
execution policy. [`ManualStub`](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md)
provides the same `when`/`then`/`verify` API on those targets with a small
hand-written conformer.

WebAssembly (`wasm32-unknown-wasip1`) has no facility for executable memory
and no register-based calling convention to hand-assemble against, so the
runtime trampoline cannot run there at all, the same limitation as physical
Apple devices, but more fundamental: it isn't a policy restriction to route
around, WASI's own `<sys/mman.h>` rejects even its mmap emulation shim for
executable pages. `Stub`/`Spy` construction fails closed there with the usual
actionable `StubError` diagnostic; use `ManualStub`. CI cross-builds the
library for `wasm32-unknown-wasip1` in debug and release with the official
Swift 6.3.1 WASI SDK, and actually runs both a small standalone executable and
the `TestDoublesWasmTests` suite under `wasmtime`, demonstrating both halves
of that story: `ManualStub` fully configured, invoked, and verified, and
`Stub` construction failing closed. The dependency graph must resolve Echo
0.0.6 or newer, whose C declarations avoid a wasm32 LLVM compiler crash on
unprototyped functions.

</details>

<details>
<summary><strong>How construction finds your protocol's signatures</strong></summary>

`try Stub<any P>()` needs a source for the protocol's requirement signatures:

| Available signature source | Construction |
| --- | --- |
| A concrete conformer is linked into the test process (usually your production implementation) | `try Stub<any P>()`. The conformance is inspected, never invoked. |
| The protocol module is built with library evolution and exports resilient requirement symbols | `try Stub<any P>()`; no conformer needed. |
| Neither | Describe the requirements explicitly with `Stub.Requirement` values; prefer the `signatureOf:` member-reference factories. |

Two cases need a small extra hint:

- **Effectful getters.** Swift's metadata never records whether a getter can
  throw, so a protocol with `get async` or `get throws` properties takes a
  `getterEffects:` list at construction, with one `.throwing` or
  `.nonthrowing` hint per getter. The hints only fix the calling convention;
  `when` still configures values as usual.
- **Class and existential values.** `when` and `verify` closures run once to
  record which requirement they name, and that recording pass needs valid
  temporary values. TestDoubles synthesizes them for most types; for class
  instances and existentials you pass any valid instance via the `using:` and
  `returning:` overloads (for example `any(using: someUser)`). The value is
  used only during recording. It is never matched against or returned.

See the [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md)
for explicit requirement forms, inheritance ordering, and compositions, and
[Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md)
for worked examples of both hints.

</details>

<details>
<summary><strong>How it works under the hood</strong></summary>

Construction is a transaction:

1. Requirement signatures are discovered from Swift runtime metadata: a
   linked conformance's records, or resilient per-requirement descriptor
   symbols. Nothing is invoked and no external tool runs.
2. A genuine witness table is fabricated whose entries all land in one fixed
   trampoline, hand-written in assembly for arm64 and x86_64
   ([`TestDoublesTrampoline.S`](Sources/CTestDoublesTrampoline/TestDoublesTrampoline.S)).
3. The trampoline captures the machine state of each call, and the runtime
   reconstructs typed arguments and results exactly per the Swift calling
   convention, including async continuations, error channels, and indirect
   returns.
4. Every reconstructed call flows through the recorder: matcher selection,
   behavior replay, and the invocation log that verification reads.
5. If any step cannot be done exactly, construction throws a `StubError`
   diagnostic and no partially-built value can escape.

Generated values own their runtime resources, so they stay valid even after
the `Stub` itself is released. The details live in
[How Runtime Stubs Work](Sources/TestDoubles/Documentation.docc/Articles/HowRuntimeStubsWork.md),
[Trampoline Architecture](Sources/TestDoubles/Documentation.docc/Articles/TrampolineArchitecture.md),
and [ARCHITECTURE.md](ARCHITECTURE.md).

</details>

<details>
<summary><strong>Support matrix and limitations</strong></summary>

What's supported:

- Instance and static methods, property getters and setters, subscripts, and
  initializer requirements, in sync, throwing, async, and async-throwing
  forms, including typed `throws` with a concrete or directly bound associated
  error type.
- Protocol inheritance, diamond bases, and multi-protocol compositions;
  class-constrained protocols, and `NSObject`-backed superclass existentials
  on Apple platforms.
- Dynamic `Self` results and automatically discovered direct or single-optional
  `Self` arguments for nonthrowing instance methods. Bound primary associated
  types cover recursive `Optional`, `Array`, `Set`, `Dictionary`, and `Result`
  values, proven linked generic classes, and the documented concrete-reference
  slice. Native Swift closures work as arguments and results.
- Borrowing property and subscript access through Swift 6.3 `read` accessors
  and Stub-side Swift 6.4 `yielding borrow`, compound assignment and `inout`
  access through `_modify`, concurrent invocation of generated values, behavior
  chains, argument captors, ordered and event-driven verification.

Key limitations:

- Unbound associated types beyond the documented caller-bound slice are
  rejected. `Self` arguments remain unsupported in explicit schemas, Spies,
  superclass-constrained existentials, throwing methods, `inout`, and wider or
  nested wrappers.
- Async Stub requirements may fill the general-purpose register bank and use up
  to eight decoded stack bytes. Async Spy forwarding and dynamic closure
  bridging narrow that allowance to one complete eight-byte general-purpose
  word; split, padded, vector, dependent, and additional spills fail closed.
- Typed-throwing getters, Objective-C-only protocols, and native-Swift-only
  superclass constraints are outside the boundary.
- Protocols that relax `Copyable` or `Escapable` are rejected because recorder
  values are retained as escaping `Any` payloads.
- Physical device targets don't run the executable trampoline; use
  `ManualStub` there.

Everything above fails closed: an unsupported shape throws an actionable
`StubError` at construction. The precise, normative contract is in the
[Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md),
with deep dives in
[Function Values](Sources/TestDoubles/Documentation.docc/Articles/FunctionValues.md)
and
[Bound Associated Types](Sources/TestDoubles/Documentation.docc/Articles/BoundAssociatedTypes.md).

</details>

## Beyond the basics

The DocC catalog covers the rest of the surface, with examples:

- [Getting Started](Sources/TestDoubles/Documentation.docc/Articles/GettingStarted.md): the guided tour.
- [Async Behaviors](Sources/TestDoubles/Documentation.docc/Articles/AsyncBehaviors.md): delays, wedged dependencies, cancellation, and test-driven suspension.
- [Inspecting Interactions](Sources/TestDoubles/Documentation.docc/Articles/InspectingInteractions.md): typed invocation access, cross-double ordering, unused-stub detection, placeholder registry, and reset.
- [Recording and Replaying Interactions](Sources/TestDoubles/Documentation.docc/Articles/RecordAndReplay.md): capture a Spy's real calls into a fixture and replay them on a plain Stub later.
- [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md): explicit requirements, getter effects, inheritance and composition ordering.
- [Forwarding Spies](Sources/TestDoubles/Documentation.docc/Articles/ForwardingSpies.md): the forwarding boundary and diagnostics.
- [Dummy Test Doubles](Sources/TestDoubles/Documentation.docc/Articles/DummyTestDoubles.md): fail-on-use placeholders.
- [Manual Stubbing](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md): the same API via a hand-written conformer, for device targets and out-of-boundary shapes.
- [Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md): the normative support and failure contract, including static and initializer requirements, dynamic `Self`, subscripts, and setters.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes, [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
standards, [SECURITY.md](SECURITY.md) for private vulnerability reporting, and
[CHANGELOG.md](CHANGELOG.md) for release changes.

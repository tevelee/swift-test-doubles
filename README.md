# swift-test-doubles

[![CI](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml/badge.svg)](https://github.com/tevelee/swift-test-doubles/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/tevelee/swift-test-doubles/branch/main/graph/badge.svg)](https://codecov.io/gh/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftevelee%2Fswift-test-doubles%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tevelee/swift-test-doubles)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Configurable Swift test doubles for protocols and closure-based
dependencies.** Point `Stub` at a protocol for a runtime-created conformance, or
build a concrete closure-field client with `ClientStub`. Both use the same
matching, behavior, recording, and verification vocabulary.

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

await auth.when { try await $0.signIn(user: Match.equal("blob"), password: Match.equal("sekret")) }
    .thenReturn("session-42")
await auth.when { try await $0.signIn(user: Match.any(), password: Match.any()) }
    .thenThrow(AuthError.invalidCredentials)

// A real `any AuthService`, ready to hand to the code under test.
let service: any AuthService = auth()

#expect(try await service.signIn(user: "blob", password: "sekret") == "session-42")
await #expect(throws: AuthError.self) {
    try await service.signIn(user: "blob", password: "hunter2")
}

await auth.verify(2 ... 2) { try await $0.signIn(user: Match.any(), password: Match.any()) }
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

flags.when { $0.isEnabled(Match.equal("new_checkout"), for: Match.equal(7)) }.thenReturn(true)
flags.when { $0.isEnabled(Match.equal("new_checkout"), for: Match.any()) }
    .then { (_: String, userID: Int) in userID.isMultiple(of: 2) }
flags.when { $0.isEnabled(Match.any(), for: Match.any()) }.thenReturn(false)

let sut: any FeatureFlags = flags()
#expect(sut.isEnabled("dark_mode", for: 1) == false)   // fallback
#expect(sut.isEnabled("new_checkout", for: 4) == true) // computed
#expect(sut.isEnabled("new_checkout", for: 7) == true) // pinned
```

`Match.any()` matches everything, `Match.matching(description:where:)` matches a
predicate, `Match.equal(_:)` matches a value, and `then` computes the answer from
the actual arguments. When several registrations match a call, the first one
wins, like the cases of a `switch`: register specific matchers first and
broad fallbacks last, because a catch-all registered first swallows
everything after it.

Use matcher expressions for every argument when recording a call that involves
an ABI-uncertain concrete value. The common case is a non-`@frozen` imported
value from a library-evolution module, but an opaque standard-library generic
value such as `ArraySlice<Int>` can need the same calibration. Those matchers
let the runtime establish the client's direct or indirect convention before it
decodes a real call. Common standard-library and framework values synthesize
their recording values automatically. These include `StaticString`,
`AnyHashable`, empty collection wrappers, `any Error`, `URLRequest`,
notifications, attributed strings, person names, common `Measurement` units,
and Foundation's URL, data, date, locale, and archive values. Dispatch values
use `.empty` or `.main`. On Combine platforms, subscriptions, type erasers,
cancellables, and subjects also work as arguments without fixtures. `Optional`,
`Result`, and `CurrentValueSubject` recursively synthesize their payloads, so
they also use ordinary `Match.any()`. Generic wrappers such as `Range<Date>`
and `ClosedRange<Date>` still need a valid example through `using:`, as does a
custom value that cannot be synthesized:

```swift
stub.when {
    $0.open(
        Match.any(),
        at: Match.any(using: importedValue)
    )
}.thenReturn(result)
```

Do this before the first ordinary or forwarded call to that requirement. A
literal-only recording has no independent calibration value for each argument.

There is a richer vocabulary for common cases. `Match.notEqual(_:)` and
`Match.identical(to:)` refine equality; `Match.greaterThan`,
`Match.atLeast`, `Match.lessThan`, `Match.atMost`, and `Match.inRange(_:)`
match `Comparable` arguments; `Match.isNil()`, `Match.notNil()`, and
`Match.some(matcher)` match optionals; `Match.isEmpty()`, `Match.nonEmpty()`,
`Match.hasCount`, `Match.contains`, `Match.containsAll`, `Match.startsWith`,
and `Match.endsWith` match collections; `Match.hasPrefix`, `Match.hasSuffix`,
`Match.containsSubstring`, `Match.equalsIgnoringCase`, and
`Match.matchesRegex` match strings; and `Match.not`, `Match.allOf`,
`Match.anyOf`, and `Match.oneOf` compose matchers with boolean logic.
Composition stays positional, so
`Match.allOf(events.capture(), Match.hasPrefix("purchase"))` captures only the
arguments that satisfy the whole expression. Use matcher functions for every
argument of a registration or none — a call cannot mix bare literals and
matchers. Literal-only registrations use `==` for `Equatable` values, identity
for references (including optionals), and equality for metatypes. A closure or
other value without a generic equality relation needs an explicit matcher, and
a mixed registration stops at `when` with a rewrite hint rather than becoming a
nonmatching stub.

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

let loads = await loader.when { try await $0.loadFeed() }
    .thenThrow(URLError(.timedOut))
    .thenThrow(URLError(.networkConnectionLost))
    .thenReturn(["Hello, world"])

let feed = FeedViewModel(loader: loader())
await feed.refresh()

#expect(feed.posts == ["Hello, world"])
#expect(feed.retryCount == 2)
loads.verify(3 ... 3)
```

Each matching call consumes the next behavior in the chain. A bare intermediate
behavior runs exactly once, while the bare trailing behavior repeats for every
call after that. Use `times: 2` for another exact finite run or `times: 1...`
when you want to make the unbounded terminal explicit. A terminal behavior
returns an observation-only handle, so the completed chain can be saved and
later verified, inspected with `arguments()`, or observed with `stream()`.
Each registration owns its own chain, so a call that matches a more specific
registration does not advance a general fallback's chain.

Computed handlers and forwarding use those same rules, so argument-dependent
work can hand off to a fixed fallback without extracting another registration:

```swift
loader.when { try await $0.loadFeed() }
    .thenForEachCall(times: 2) { attempt in try await remote.load(attempt: attempt) }
    .thenReturn(["offline"])
```

That observation handle is common to terminal configuration: custom `then`
handlers, `thenForEachCall`, forwarding, cancellation, record/replay, and
initializer or dynamic-`Self` builders can all be saved and verified the same
way. Specialized controls compose it instead: use `suspension.interactions` or
`queue.interactions` while retaining their resume or exhaustion operations.

When the response depends on *which* attempt this is rather than a fixed list,
`thenForEachCall` hands the computed handler a running call count as its first
argument, ahead of the requirement's typed arguments:

```swift
loader.when { try await $0.loadFeed() }.thenForEachCall { attempt in
    if attempt < 3 { throw URLError(.timedOut) }
    return ["Hello, world"]
}
```

The count starts at 1 and increments once per call served by that behavior.
Appending another counted behavior starts it again at 1. Trailing arguments may
be omitted, so a handler can take the count alone or the count followed by a
leading prefix of the requirement's arguments.

### Double injected closures

Injected function values use the same `when → then → verify` model without
inventing a protocol:

```swift
let formatter = ClosureDouble<Int, String>()
let twos = formatter.when(equal: 2)
let twoCalls = twos
    .thenReturn("first two")
    .thenReturn("two")
formatter.whenAny().then { "other-\($0)" }

let format: (Int) -> String = formatter.function
#expect(format(2) == "first two")
#expect(format(2) == "two")
#expect(format(9) == "other-9")

twoCalls.verify(2 ... 2)
#expect(twos.arguments() == [2, 2])
```

`ClosureCallPattern` preserves the input type for handler, argument, and stream
inference while sharing the same behavior queues, contextual trailing defaults,
`CallInteractions`, count ranges, strict-scope diagnostics, and
`InvocationOrder` engine as protocol doubles. `VoidClosureDouble` provides the
same model for `() -> Result`.

Choose the double that matches the injected closure's effects; its pattern
offers only valid outcomes in autocomplete:

```swift
let load = AsyncThrowingClosureDouble<URL, Data>()
let loads = load.whenAny()
    .thenThrow(URLError(.timedOut))
    .then { (url: URL) async throws in try await cache.data(for: url) }
    .thenReturn(Data())

let function: (URL) async throws -> Data = load.function
_ = try? await function(feedURL)
loads.verify()
```

`ThrowingClosureDouble` models `(Input) throws -> Result`,
`AsyncClosureDouble` models `(Input) async -> Result`, and
`AsyncThrowingClosureDouble` models `(Input) async throws -> Result`. Async
patterns also share delayed results, suspension, and cancellation controls with
protocol stubs.

Multi-argument closures use a tuple input and expand back to an ordinary
function of any arity:

```swift
let format = AsyncThrowingClosureDouble<(Int, String, Bool), String>()
format.whenArguments { (count: Int, _: String, enabled: Bool) in
    count > 0 && enabled
}.thenArguments { (count: Int, unit: String, _: Bool) async throws in
    "\(count) \(unit)"
}

let function: (Int, String, Bool) async throws -> String =
    format.expandedFunction()
```

Use `ClientStub` when those closures belong to one concrete dependency value:

```swift
struct APIClient {
    var fetch: @Sendable (Int, String) async throws -> Data
    var track: @Sendable (String) -> Void
}

let api = ClientStub<APIClient> { endpoints in
    APIClient(
        fetch: endpoints.asyncThrowingFunction("fetch"),
        track: endpoints.function("track")
    )
}

await api.when {
    try await $0.fetch(Match.equal(42), Match.any())
}.thenReturn(Data())
api.when { $0.track(Match.any()) }.thenDoNothing()

let client: APIClient = api()
```

All client endpoints share one recorder, including nullary and high-arity
sync, throwing, async, and async-throwing operations. This construction path
does not use protocol metadata or executable trampolines, and works with the
`RuntimeStubs` package trait disabled. See
[Closure-Based Dependencies](Sources/TestDoubles/Documentation.docc/Articles/ClosureClients.md).

Reuse the wiring for fail-closed tests and live forwarding with
`ClientDoublePreset`:

```swift
let apiClients = ClientDoublePreset<APIClient> { endpoints in
    APIClient(
        fetch: endpoints.asyncThrowingFunction(
            "fetch",
            forwarding: { live, id, category in
                try await live.fetch(id, category)
            }
        ),
        track: endpoints.function(
            "track",
            forwarding: { live, event in live.track(event) }
        )
    )
}

let spy = await apiClients.spy(forwardingTo: liveAPI) {
    await $0.when {
        try await $0.fetch(Match.equal(42), Match.any())
    }.thenReturn(Data())
}

let client = spy() // unmatched calls forward and every call is recorded
```

`live(_:)`, `failing()`, `spy(forwardingTo:)`, and
`overriding(_:configure:)` cover environment-style dependency presets without
repeating field mappings. Each controller factory accepts synchronous and
asynchronous configuration closures. When later verification is unnecessary,
`testValue { ... }` and `testValue(overriding: live) { ... }` return a concrete
dependency value directly.

With the opt-in `StubbableMacros` trait, `@StubbableClient` derives this wiring
as `APIClientDoubles.preset`. The macro supports ordinary generic clients,
nested closure type aliases, custom initializers, required non-closure
configuration inputs, and initialized immutable closure defaults. Name global,
imported, or generic closure-alias fields in `aliasedEndpoints` so the generated
wiring can use their declared function type directly.

### Control async timing

Testing async code often means asserting what happens *while* a call is in
flight, not just what it returns. Configure the timing of a completion with the
same vocabulary, no `Task.sleep` required.

```swift
let loader = try Stub<any FeedLoader>()
let suspension = await loader.when { try await $0.loadFeed() }.thenSuspend()

let feed = FeedViewModel(loader: loader())
let refresh = Task { await feed.refresh() }

await suspension.waitForCall(within: .seconds(1))
#expect(feed.isLoading)
suspension.interactions.verify(1 ... 1)

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
let allEvents = analytics.when {
    $0.track(event: Match.any(), value: Match.any())
}
allEvents.thenDoNothing()

let checkout = Checkout(analytics: analytics())
checkout.add(item: "socks", price: 30)
checkout.add(item: "hat", price: 12)
checkout.placeOrder()

let purchase = analytics.when {
    $0.track(event: Match.equal("purchase"), value: Match.equal(42))
}
purchase.verify()

let errors = analytics.when {
    $0.track(event: Match.equal("error"), value: Match.any())
}
errors.verify(.never)

allEvents.verify(3 ... 3)
let events: [(String, Int)] = allEvents.arguments()
#expect(events.map(\.0) == ["add_to_cart", "add_to_cart", "purchase"])

analytics.verifyInOrder {
    $0.track(event: Match.equal("add_to_cart"), value: Match.any())
    $0.track(event: Match.equal("purchase"), value: Match.any())
}
```

When the call happens on another task, wait for it instead of sleeping:

```swift
let syncCompleted = analytics.when {
    $0.track(event: Match.equal("sync_completed"), value: Match.any())
}
await syncCompleted.verify(1..., within: .seconds(1))
```

`when` creates a reusable `CallPattern`: configure its behavior, verify it,
read its typed arguments, and observe future matches without describing the
same call again. A plain `verify()` expects exactly one call. Use native ranges
such as `1...`, `...2`, or `2...4` for every other count shape; `.exactly(2)`
and `.never` are secondary conveniences for the two cases that ranges spell
less clearly.
`verifyInOrder` checks a relative subsequence, so unrelated calls may appear
between the listed ones. Verification never consumes configured behavior, and
failures are reported as test issues at the `verify` call's own file and
line. There is also `verifyNoMoreInteractions()` to catch calls no successful
verification has covered.

Use `history` when the assertion concerns the double as a whole rather than one
requirement. The same handle composes spy dispatch filtering and diagnostics:

```swift
#expect(analytics.history.callCount == 3)
analytics.history.verify(3 ... 3)
print(analytics.history.timeline)

spy.history.forwarded.verify(1...)
spy.history.stubbed.verify()
```

With Swift Testing, add the `TestDoublesTesting` product to your test target,
then write `@Test(.testDoubles)` to make unused registrations a teardown
failure for every `Stub`, `Spy`, or `ManualStub` created in that test. Use
`@Test(.strictTestDoubles)` to also require that every interaction is verified,
every finite response queue is consumed, every `thenSuspend()` call is resumed,
and every `CallbackCapture` is released.

For custom assertions, read a pattern's recorded arguments as typed tuples with
`arguments()`; `describeInteractions()` dumps the whole call log as a
human-readable, ordered string when a failing `verify` leaves you asking what
actually got called; `InvocationOrder` captures repeated method invocations in
an ordered builder and also accepts saved patterns or terminal interaction
handles; `verifyNoUnusedStubs()` flags registrations no call matched; and
`reset()` restores a double between parameterized cases. See
[Inspecting Interactions](Sources/TestDoubles/Documentation.docc/Articles/InspectingInteractions.md).

```swift
let events: [(String, Int)] = allEvents.arguments()
#expect(events == [("add_to_cart", 30), ("add_to_cart", 12), ("purchase", 42)])

InvocationOrder(exhaustive: true) {
    gateway().charge(amount: 42)
    analytics().track(event: "purchase", value: 42)
}
```

For event-driven code, `stream()` yields matching calls made after the stream
is created, without polling:

```swift
let events: InvocationStream<(String, Int)> = allEvents.stream()

var iterator = events.makeAsyncIterator()
let call = try #require(await iterator.next(within: .seconds(1)))
#expect(call.0 == "purchase")
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
spy.when { $0.translate(Match.equal("greeting.new_user")) }.thenReturn("Howdy, partner")
let translations = spy.when { $0.translate(Match.any()) }

let translator: any Translator = spy()
#expect(translator.translate("greeting.new_user") == "Howdy, partner") // overridden
#expect(translator.translate("farewell.title") == "Goodbye")           // forwarded

translations.verify(2 ... 2)

translations.forwarded.verify(1...)
let forwarded: [String] = translations.forwarded.arguments()
#expect(forwarded == ["farewell.title"])

translations.stubbed.verify()
let stubbed: [String] = translations.stubbed.arguments()
#expect(stubbed == ["greeting.new_user"])
```

A matching `when` registration wins, and the first matching one is used,
just as with `Stub`. Every other supported call forwards to the target and
is recorded, so verification covers overridden and forwarded calls alike. The target's conformance also supplies the signature metadata,
so a spy needs no other discovery source. A registration can also hand a call
back to the real implementation explicitly with `thenForward()`, which lets a
chain fail a few times and then forward for real.

`forwarded` and `stubbed` are symmetric filtered `CallInteractions` views.
Both support the same counts, ranges, typed arguments, streams, eventual
verification, and `InvocationOrder` composition as the unfiltered pattern.

### Dummy: dependencies that must never be touched

When an initializer demands a dependency the exercised code path must not
use, pass a dummy. `Dummy.make()` fabricates supported protocol existentials,
concrete values, and functions. Protocol and function calls fail with an
actionable diagnostic, which is a stronger guarantee than a silent no-op mock.

```swift
let checkout = Checkout(
    gateway: gateway(),
    analytics: Dummy.make() // protocol existential
)

let context: CheckoutContext = Dummy.make()       // constructible struct
let completion: (Receipt) -> Void = Dummy.make()  // fail-on-use closure
```

Scalars, strings, empty collections, tuples, structs, direct enum cases,
metatypes, `Any`, `AnyObject`, and supported function conventions are
synthesized automatically. Supply `Dummy.make(using:)` for a class or custom
invariant, or register one reusable exact-type factory with
`Dummy<YourType>.register`.

### One-shot stubs

When a test only needs a configured value and no verification afterward,
there is a shorthand:

```swift
let translator: any Translator = Stub.make {
    $0.when { $0.translate(Match.any()) }.then { (key: String) in "«\(key)»" }
}
```

Keep an explicit `Stub` when the test needs verification, reconfiguration, or
the generated value more than once.

### Reuse named setup

Use a scenario to share ordinary `when` registrations while keeping the test's
stub and verification close to the behavior under test:

```swift
let signedOut: StubScenario<any AccountService> = .init {
    $0.when { $0.currentUser() }.thenReturn(nil)
}

let account = try Stub<any AccountService>()
signedOut.apply(to: account)
```

Scenarios compose in first-match-wins registration order with `appending(_:)`.
Use `AsyncStubScenario` when the setup records async requirements.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/tevelee/swift-test-doubles",
        .upToNextMinor(from: "0.0.2")
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

`RuntimeStubs` is enabled by default, preserving the complete `Stub`, `Spy`,
and `Dummy` API. A target that uses only `ManualStub` can omit runtime
fabrication, Echo, and swift-atomics from its build graph by disabling this
package's default traits:

```swift
.package(
    url: "https://github.com/tevelee/swift-test-doubles",
    .upToNextMinor(from: "0.0.2"),
    traits: []
)
```

Runtime-generated double construction then fails with a diagnostic that
explains how to re-enable `RuntimeStubs`; manual stubs keep the same
`TestDoubles` import and API.

## The fine print

<details>
<summary><strong>Requirements and platforms</strong></summary>

TestDoubles requires Swift 6.3. Its declared deployment targets are macOS 13+,
Mac Catalyst 16+, iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+. CI builds
against those minima and runtime-tests on pinned macOS 26 arm64 and x86_64
hosts, Linux arm64 and x86_64 hosts, and the oldest available arm64 simulator
runtime installed with the pinned Xcode. Android arm64 and x86_64 are
provisional cross-build targets, and wasm32-unknown-wasip1 is a
`ManualStub`-only target.

Android support is cross-build validated in CI for debug and release test
targets with the official Swift 6.3.3 Android SDK and NDK r27d or later. The
dependency graph must resolve Echo 0.1.1 or newer for Android ELF image
discovery. CI also runs a focused x86_64 emulator demonstration that fabricates,
configures, invokes, and verifies a `Stub`. The full test suites do not
currently execute on an Android emulator or device, so Android remains
provisional.

Physical iOS, tvOS, visionOS, and watchOS devices are unsupported because the
runtime generates executable trampoline code and CI cannot exercise device
execution policy. [`ManualStub`](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md)
provides the same `when`/`then`/`verify` API on those targets with a small
hand-written conformer.

A macOS test process must be allowed to map JIT memory. The runtime allocates
its trampoline pages with `MAP_JIT`, which the kernel rejects with `EINVAL` in
any process signed with the hardened runtime and without the
`com.apple.security.cs.allow-jit` entitlement. Construction then fails closed
with `Could not allocate an executable trampoline for requirement 0`, where the
index only names the first witness slot that was attempted. Command-line
`swift test` binaries are unaffected. Xcode app test targets running on **My
Mac** are affected whenever the host app enables the hardened runtime, because
the `.xctest` bundle is loaded into that host process. Enable the entitlement
on the **host app target**, not on the test bundle:

| Fix | Build setting | Xcode UI |
| --- | --- | --- |
| Allow JIT (recommended) | `RUNTIME_EXCEPTION_ALLOW_JIT = YES` | Signing & Capabilities, Hardened Runtime, "Allow Execution of JIT-compiled Code" |
| Drop the hardened runtime from the test configuration | `ENABLE_HARDENED_RUNTIME = NO` | Build Settings, "Enable Hardened Runtime" |
| Run the tests on a simulator destination | none | pick a simulator instead of My Mac |

```bash
xcodebuild test -scheme YourApp -destination 'platform=macOS' RUNTIME_EXCEPTION_ALLOW_JIT=YES
```

Removing `MAP_JIT` is not a workaround. A plain anonymous mapping can still be
`mprotect`ed to read-execute under the hardened runtime, but executing it
terminates the process with `SIGKILL` under code-signing enforcement, so the
runtime maps `MAP_JIT` and reports the mapping failure instead.

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
0.1.1 or newer, whose C declarations avoid a wasm32 LLVM compiler crash on
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
  `returning:` overloads (for example `Match.any(using: someUser)`). The value is
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
  values, proven linked generic classes, structs, and enums, and the documented
  concrete-reference slice. Native Swift closures work as arguments and results.
- Borrowing property and subscript access through Swift 6.3 `read` accessors
  and Stub-side Swift 6.4 `yielding borrow`, compound assignment and `inout`
  access through `_modify`, concurrent invocation of generated values, behavior
  chains, argument captors, ordered and event-driven verification.
- Requirement-level generic methods, including async and typed-throwing
  stubs, caller-chosen generic results, and forwarding spies for unconstrained
  or `AnyObject`-constrained parameters.

Key limitations:

- Unbound associated types beyond the documented caller-bound slice are
  rejected. `Self` arguments remain unsupported in explicit schemas, Spies,
  superclass-constrained existentials, throwing methods, `inout`, and wider or
  nested wrappers.
- Async Stub requirements may fill the argument-register banks and use the
  documented complete integer, floating-point, SIMD, indirect, and
  platform-correct narrow stack shapes. Async Spy forwarding retains up to
  eight visible stack words; dynamic closure bridging has a separate one-word
  stack boundary.
- Typed-throwing getters require explicit `signatureOf:` requirements and are
  not forwarded by Spy. Objective-C-only protocols and native-Swift-only
  superclass constraints are outside the boundary.
- Protocols that relax `Copyable` or `Escapable` are rejected because recorder
  values are retained as escaping `Any` payloads.
- Physical device targets don't run the executable trampoline; use
  `ManualStub` there.
- A macOS test host signed with the hardened runtime cannot map the
  trampoline's JIT pages until the host app carries the
  `com.apple.security.cs.allow-jit` entitlement
  (`RUNTIME_EXCEPTION_ALLOW_JIT = YES`).

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
- [Reusable Scenarios](Sources/TestDoubles/Documentation.docc/Articles/ReusableScenarios.md): named, composable setup for generated and manual stubs.
- [Recording and Replaying Interactions](Sources/TestDoubles/Documentation.docc/Articles/RecordAndReplay.md): capture a Spy's real calls into a fixture and replay them on a plain Stub later.
- [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md): explicit requirements, getter effects, inheritance and composition ordering.
- [Forwarding Spies](Sources/TestDoubles/Documentation.docc/Articles/ForwardingSpies.md): the forwarding boundary and diagnostics.
- [Dummy Test Doubles](Sources/TestDoubles/Documentation.docc/Articles/DummyTestDoubles.md): fail-on-use placeholders.
- [Manual Stubbing](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md): the same API via a hand-written conformer, for device targets and out-of-boundary shapes.
- [Closure-Based Dependencies](Sources/TestDoubles/Documentation.docc/Articles/ClosureClients.md): concrete closure-field clients and arbitrary-arity standalone function doubles.
- [Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md): the normative support and failure contract, including static and initializer requirements, dynamic `Self`, subscripts, and setters.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes, [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
standards, [SECURITY.md](SECURITY.md) for private vulnerability reporting, and
[CHANGELOG.md](CHANGELOG.md) for release changes.

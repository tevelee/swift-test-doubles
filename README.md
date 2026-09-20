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

Requires Swift 6.3+. [Add TestDoubles to your test target](#installation), then
choose the example that matches your dependency:

| Your dependency | Start with |
| --- | --- |
| A protocol with an existing implementation, on a runtime-capable test host | [Protocol stub](#protocol-stub) |
| A struct containing closures | [Closure client](#closure-client) |
| A protocol that needs generated conformance or physical-device support | [Generated conformer](#generated-conformer) |

Each example is a complete Swift Testing source file. All three follow the
same workflow: construct, configure with `when` and `thenReturn`, inject the
value, and `verify` its calls.

### Protocol stub

Use an existing implementation as the source of the protocol's signatures.
TestDoubles inspects its conformance without invoking or retaining it:

<!-- readme-example: ProtocolExample -->
```swift
import Testing
import TestDoubles

protocol GreetingService {
    func greet(_ name: String) -> String
}

struct LiveGreetingService: GreetingService {
    func greet(_ name: String) -> String { "Hello, \(name)!" }
}

@Test func protocolStub() throws {
    let greetings = try Stub<any GreetingService>(
        discoveringFrom: LiveGreetingService()
    )
    greetings.when { $0.greet(Match.equal("Blob")) }.thenReturn("Welcome!")
    greetings.when { $0.greet(Match.any()) }.thenReturn("Hello!")

    let service: any GreetingService = greetings()
    #expect(service.greet("Blob") == "Welcome!")
    #expect(service.greet("Ada") == "Hello!")
    greetings.verify(2 ... 2) { $0.greet(Match.any()) }
}
```
<!-- /readme-example -->

The first matching registration wins: put specific cases before broad
fallbacks. When the test process already exposes enough signature metadata,
`try Stub<any GreetingService>()` also works without passing an instance.
See the [Construction Guide](Sources/TestDoubles/Documentation.docc/Articles/ConstructionGuide.md)
for that route and for protocols without an existing implementation.

### Closure client

For a dependency whose operations are stored closures, wire those fields with
`ClientStub`. This route also works with runtime support disabled:

<!-- readme-example: ClientExample -->
```swift
import Testing
import TestDoubles

struct GreetingClient {
    var greet: @Sendable (String) -> String
}

@Test func closureClient() {
    let greetings = ClientStub<GreetingClient> { endpoints in
        GreetingClient(greet: endpoints.function("greet"))
    }
    greetings.when { $0.greet(Match.any()) }.thenReturn("Welcome!")

    let client = greetings()
    #expect(client.greet("Blob") == "Welcome!")
    greetings.verify(1 ... 1) { $0.greet(Match.equal("Blob")) }
}
```
<!-- /readme-example -->

See [Closure-Based Dependencies](Sources/TestDoubles/Documentation.docc/Articles/ClosureClients.md)
for async fields, reusable presets, and forwarding to a live client.

### Generated conformer

Attach the build plugin to the target containing your protocol declaration.
It generates and compiles the conformer whenever the protocol changes:

<!-- readme-example: PortableTarget -->
```swift
.testTarget(
    name: "PortableExample",
    dependencies: [
        .product(name: "TestDoubles", package: "swift-test-doubles")
    ],
    plugins: [
        .plugin(name: "ManualStubBuildPlugin", package: "swift-test-doubles")
    ]
)
```
<!-- /readme-example -->

Place this source file in `Tests/PortableExample`. The plugin supplies
`WeatherServiceStub`; no hand-written conformer or macro is needed:

<!-- readme-example: PortableExample -->
```swift
import Testing
import TestDoubles

protocol WeatherService {
    func forecast(for city: String) -> String
}

@Test func generatedConformer() {
    let weather = TestDouble.stub(using: WeatherServiceStub.self)
    weather.when { $0.forecast(for: Match.any()) }.thenReturn("Sunny")

    let service: any WeatherService = weather()
    #expect(service.forecast(for: "Budapest") == "Sunny")
    weather.verify(1 ... 1) { $0.forecast(for: Match.equal("Budapest")) }
}
```
<!-- /readme-example -->

This factory selects runtime construction when supported and otherwise uses
the generated conformer, including on physical Apple devices and with runtime
support disabled. Use `WeatherServiceStub()` to always select compiled
dispatch. See [Manual Stubbing](Sources/TestDoubles/Documentation.docc/Articles/ManualStubbing.md)
for generation options and supported protocol declarations.

Runtime protocol doubles require a supported test host and protocol shape;
construction throws a diagnostic when either is unavailable. The
[Runtime Compatibility](Sources/TestDoubles/Documentation.docc/Articles/RuntimeCompatibility.md)
article covers platforms, signing, and ABI limits. For the implementation,
see [How Runtime Stubs Work](Sources/TestDoubles/Documentation.docc/Articles/HowRuntimeStubsWork.md).

## What you can do

### Shape responses per argument

Matchers pick the response in registration order. The first matching
registration wins, so register specific cases before general fallbacks.

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

For imported values or custom types that need recording placeholders, see
[Quick Start](Sources/TestDoubles/Documentation.docc/Articles/QuickStart.md).

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
arguments that satisfy the whole expression. Literals and matchers may share a
call when TestDoubles can unambiguously associate each matcher with one
argument. Literal positions use `==` for `Equatable` values, identity for
references (including optionals), and equality for metatypes. If same-typed
values make matcher placement ambiguous, registration stops with a rewrite hint; spell pinned values with
`Match.equal(_:)` or `Match.identical(to:)` to make every position explicit.

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
dependency value directly. `ClientDoublePreset` and `testValue` are ordinary
library API: no macro, and no `StubbableMacros` trait, is required to use them.

With the opt-in `StubbableMacros` trait, `@StubbableClient` additionally
derives the `ClientDoublePreset` wiring for you, as `APIClientDoubles.preset`,
from a closure-field struct's stored properties. The macro supports ordinary
generic clients, nested closure type aliases, custom initializers, required
non-closure configuration inputs, and initialized immutable closure defaults.
Name global, imported, or generic closure-alias fields in `aliasedEndpoints` so
the generated wiring can use their declared function type directly.

Use the hand-written preset directly with swift-dependencies, TCA, or another
environment-style dependency system. No TestDoubles macro is involved:

```swift
extension APIClient: TestDependencyKey {
    static var testValue: Self { apiClients.testValue() }
}

@Test(
    .dependencies {
        $0.apiClient = await apiClients.testValue { stub in
            await stub.when { try await $0.fetch(Match.equal(42)) }
                .thenReturn(Data())
        }
    }
)
func loadsFromTheConfiguredDependency() async throws {
    @Dependency(\.apiClient) var apiClient
    _ = try await apiClient.fetch(42)
}
```

The macro-generated namespace is shorthand for the same API:
`APIClientDoubles.testValue` is equivalent to `apiClients.testValue()`, and
`APIClientDoubles.preset.testValue { ... }` is equivalent to the configured
manual form above. If the generated preset needs non-closure inputs, the
namespace emits a matching `testValue(...)` function. TCA tests can assign
either form directly through `store.dependencies`.

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

For dependencies that return `AsyncStream` or `AsyncThrowingStream`, keep the
sequence itself under test control:

```swift
let events = stub.whenStream { $0.events() }
let controller = events.thenStream(bufferingPolicy: .bufferingNewest(10))

controller.yield(.connected)
controller.yield(.message("Hello"))
controller.finish()

events.verify()
```

`thenThrowingStream()` adds `finish(throwing:)`. Both controllers expose whether
the consumer finished or cancelled iteration, and strict Swift Testing scopes
report controllers that remain open at teardown.

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

### Scoped configuration

Use `configure` to keep related registrations beside construction while
retaining the stub for verification or later reconfiguration:

```swift
let translator = try Stub<any Translator>().configure {
    $0.when { $0.translate("welcome") }.thenReturn("Bienvenue")
    $0.when { $0.translate(Match.any()) }.thenReturn("Missing translation")
}

translator.verify(.never) { $0.translate(Match.any()) }
```

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
        .upToNextMinor(from: "0.0.3")
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
    .upToNextMinor(from: "0.0.3"),
    traits: []
)
```

Runtime-generated double construction then fails with a diagnostic that
explains how to re-enable `RuntimeStubs`; manual stubs keep the same
`TestDoubles` import and API.

## The fine print

See [Runtime Compatibility](Sources/TestDoubles/Documentation.docc/Articles/RuntimeCompatibility.md)
for platform requirements, host signing, signature discovery, and ABI limits.
The [Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md)
is the normative support reference.

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

Run `python3 Scripts/validate-readme-examples.py` to compile and execute the
marked quick-start examples directly from this README. Use `--configuration release` to check optimized builds and
`--disable-runtime` to check the closure client and generated conformer without runtime support. CI runs all four
combinations, including the build-plugin target declaration above.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the validation matrix and runtime
architecture notes, [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community
standards, [SECURITY.md](SECURITY.md) for private vulnerability reporting, and
[CHANGELOG.md](CHANGELOG.md) for release changes.

# Quick Start

Create a protocol double, configure its behavior, pass the generated value to
the subject under test, and inspect the calls that came back.

## Overview

TestDoubles follows one small workflow:

1. Construct a ``Stub``, ``Spy``, or closure double.
2. Describe a call once with `when`.
3. Attach its behavior with a `then` method.
4. Inject the generated protocol value or function.
5. Verify or inspect the saved call pattern.

This page introduces the complete everyday vocabulary. Continue with
<doc:GettingStarted> for properties, subscripts, initializers, dynamic `Self`,
and associated types; <doc:AsyncBehaviors> for precise async control; and
<doc:InspectingInteractions> for deeper observation and ordering.

Tests using `.testDoubles` or `.strictTestDoubles` also record nonempty
interaction timelines as Swift Testing text attachments. They appear with the
test result when a failure needs deeper diagnosis.

Strict scopes additionally report a double whose generated protocol value,
injected closure, or controller remains alive after the test body returns. Use
`.testDoubles(strictness: [.noEscapedTestDoubles])` to enable only this lifetime
check.

They also report async invocations that are still running when the test body
returns. Use `.testDoubles(strictness: [.noUnfinishedAsyncInvocations])` to
enable only this completion check.

Invocation streams created inside a strict scope must consume every matching
call they observe or end through task cancellation. Use
`.testDoubles(strictness: [.noUnconsumedInvocationStreams])` to enable only
this stream check.

Scoped doubles receive stable automatic names derived from the current test.
Parameterized tests add a `case` qualifier and restart the double ordinal for
each case, so concurrent cases never share a process-global counter. Calling
`named(_:)` still replaces the automatic name with the domain-specific label
you supply.

### Define the dependency

The subject under test should already depend on a protocol:

```swift
protocol AuthService: Sendable {
    func signIn(
        user: String,
        password: String
    ) async throws -> String

    func signOut() async
}

enum AuthError: Error {
    case invalidCredentials
}
```

### Construct a stub

When a concrete conformer is linked into the test process, or the protocol
exports resilient requirement descriptors, zero-argument construction discovers
the requirement signatures automatically:

```swift
let auth = try Stub<any AuthService>()
```

The production conformer is inspected but never invoked. Construction throws a
``StubError`` if the protocol cannot be represented safely.

### Match calls and attach behavior

`when` records one requirement invocation and returns a reusable
``CallPattern``:

```swift
let blobSignIns = await auth.when {
    try await $0.signIn(
        user: Match.equal("blob"),
        password: Match.equal("sekret")
    )
}

blobSignIns.thenReturn("session-42")
```

Add a broad fallback after the specific registration:

```swift
await auth.when {
    try await $0.signIn(
        user: Match.any(),
        password: Match.any()
    )
}.thenThrow(AuthError.invalidCredentials)

await auth.when {
    await $0.signOut()
}.thenDoNothing()
```

Registrations use first-match-wins ordering, like the cases in a `switch`.
Register specific matchers before general fallbacks. TestDoubles reports a new
registration when an earlier registration provably makes it unreachable.

When a call has no matching registration, its diagnostic ends with
copy/paste-ready `when` code built from the actual argument labels and values.
Non-`Void` suggestions use a deliberate `fatalError("TODO: configure …")`
handler, so the pasted registration compiles for any result type and keeps the
unfinished return behavior visible.

Every argument in one recorded invocation must either use a matcher or use its
literal value. Literals compare `Equatable` values with `==`, reference values
(including optional references) by identity, and metatypes by equality. Values
without a generic equality relation, such as closures, need a `Match`
expression. Do not mix the two styles in one call: TestDoubles rejects a mixed
recording immediately; rewrite a pinned value as `Match.equal(value)` or
`Match.identical(to: object)`.

For a call involving an ABI-uncertain concrete value, prefer the matcher form
for every argument from the first recording onward. A non-`@frozen` value from
a library-evolution module may be passed directly or by address, and those
matcher placeholders let TestDoubles calibrate the client's convention before
it decodes a real call. The same rule applies to an imported generic struct or
enum, even when its current payload looks direct, because runtime metadata does
not expose whether the outer declaration is `@frozen`. Some opaque
standard-library generics, such as `ArraySlice<Int>`, have the same runtime
ambiguity even though they are not imported values. Common standard-library
and framework values synthesize their recording values automatically. These
include `StaticString`, `AnyHashable`, empty collection wrappers, `any Error`,
`URLRequest`, notifications, attributed strings, person names, common
`Measurement` units, and Foundation's URL, data, date, locale, and archive
values. Dispatch values use `.empty` or `.main`. On Combine platforms,
subscriptions, type erasers, cancellables, and subjects also work as arguments
without fixtures. `Optional`, `Result`, and `CurrentValueSubject` recursively
synthesize their payloads and use ordinary `Match.any()`. This does not make an
ABI-uncertain framework value, such as an `AnyPublisher` result, a supported
result shape. Generic wrappers such as `Range<Date>` and `ClosedRange<Date>`
still need a valid example through `using:`, as does a custom type without a
synthesizable placeholder:

```swift
stub.when {
    $0.open(
        Match.any(),
        at: Match.any(using: importedValue)
    )
}.thenReturn(result)
```

A literal-only recording cannot establish that convention independently for
every argument. Configure or verify the requirement before its first ordinary
or forwarded call.

### Adapt imported value results through the compiler

An imported non-`@frozen` value can be an argument because the matcher call
gives TestDoubles bytes to compare with the caller's frame. The same value as a
result cannot be calibrated: the caller has already chosen registers or result
storage before a fabricated witness can observe anything. For common
Foundation leaves, TestDoubles solves that problem automatically. The built-in
placeholder catalog also contains compiler-emitted result adapters for
zero-argument methods and getters across synchronous, throwing, async, and
async-throwing requirements:

```swift
protocol Loader {
    func load() async throws -> Data
}

let loader = try Stub<any Loader>()
await loader.when { try await $0.load() }.thenReturn(Data())

#expect(try await loader().load() == Data())
```

The catalog covers `URL`, `Data`, `Date`, `UUID`, `Calendar`, `Locale`,
`TimeZone`, `IndexPath`, `IndexSet`, `DateInterval`, `CharacterSet`, `Decimal`,
notification values, `AttributedString`, `PersonNameComponents`, and
`URLRequest` where available. Each entry records the return transport selected
by the compiler; no application compiler flag or runtime ABI guess is involved.
Swift 6.3 exposes the direct-transport entries, including `Data`, `Decimal`, and
`Notification.Name`; Swift 6.4 and newer also expose the indirect entries.

An explicit adapter is still needed for a non-frozen type outside that catalog,
or when the requirement has arguments. The same limitation applies to a generic
struct or enum because the runtime cannot see the outer declaration's `@frozen`
status. It is not a matcher configuration problem, so adding more
`Match.any(using:)` calls will not make a return value safe. Supply an explicit
requirement with an exact compiler-typed `@convention(thin)` adapter when the
requirement has room for its trailing ``Stub/Invocation``:

```swift
let adapter:
    @convention(thin) (
        Stub<any LocationService>.Invocation
    ) -> URL = { invocation in
        invocation.call()
    }

let locations = try Stub<any LocationService>(
    .method(returning: URL.self, using: adapter)
)
let fixture = URL(filePath: "/fixture")
locations.when(returning: fixture) {
    $0.currentLocation()
}.thenReturn(fixture)
```

The adapter is compiled in the client context, so its argument and result ABI
matches the protocol witness without runtime frozen-ness inference. It repeats
the requirement's exact explicit arguments and effects, then appends
``Stub/Invocation``. Use `callThrowing` for untyped throwing requirements and
the async overloads for async requirements. A mismatched or non-thin adapter
fails during construction. Typed-error buffers and ABI-uncertain arguments
remain outside this adapter slice. Use <doc:ManualStubbing> when the adapter
cannot be installed.

If you own the returned type, marking it `@frozen` is a permanent ABI promise
to every client, not a testing switch. Make that API decision only when its
stored layout is deliberately stable.

Reusable matcher packages can conform a value to ``CustomMatcher``:

```swift
struct MultipleOf: CustomMatcher {
    let divisor: Int

    var diagnosticDescription: String { "multipleOf(\(divisor))" }
    func matches(_ value: Int) -> Bool { value.isMultiple(of: divisor) }
}

stub.when {
    $0.record(Match.custom(MultipleOf(divisor: 3)))
}.thenDoNothing()
```

Use `Match.custom(using:_:)` when the argument type requires an explicit
recording placeholder.

### Inject the generated value

Calling the controller produces an ordinary protocol existential:

```swift
let service: any AuthService = auth()

let session = try await service.signIn(
    user: "blob",
    password: "sekret"
)

#expect(session == "session-42")
```

The generated value owns its runtime resources and may outlive the ``Stub``
controller that created it.

### Verify the saved pattern

The pattern returned by `when` keeps the call and its matchers available:

```swift
blobSignIns.verify()

let arguments: [(String, String)] = blobSignIns.arguments()
#expect(arguments == [("blob", "sekret")])
```

A plain immediate `verify()` expects exactly one call. Use native integer
ranges for every other count:

```swift
blobSignIns.verify(2 ... 2)  // exactly two
blobSignIns.verify(2...)     // at least two
blobSignIns.verify(...2)     // at most two
blobSignIns.verify(2 ... 4)  // between two and four
blobSignIns.verify(.never)   // exactly zero
```

When the call arrives from another task, wait for a monotonic lower bound:

```swift
await blobSignIns.verify(
    1...,
    within: .seconds(1)
)
```

A timeout reports a test issue at the verification call site.

### Match arguments

The `Match` namespace keeps the common matcher vocabulary discoverable through
autocomplete.

#### Values and predicates

```swift
Match.any()
Match.equal(42)
Match.notEqual(0)
Match.greaterThan(10)
Match.atLeast(10)
Match.lessThan(100)
Match.atMost(100)
Match.inRange(10 ..< 20)

Match.matching(description: "positive") {
    $0 > 0
}
```

Use ``Match/any(using:)`` or
``Match/matching(using:description:where:)`` when the recording pass cannot
safely synthesize a temporary class, existential, or custom imported value.
Common standard-library and framework values, along with recursively populated
`Optional` and `Result` wrappers, use the zero-argument forms. Imported generic
wrappers such as `Range<Date>` and `ClosedRange<Date>` need `using:` even when
their bounds are common Foundation values. A supplied value is never matched
against or returned.

#### Optionals, collections, and strings

```swift
Match.isNil()
Match.notNil()
Match.some(Match.greaterThan(0))

Match.isEmpty()
Match.nonEmpty()
Match.hasCount(3)
Match.hasCount(matching: Match.atLeast(2))
Match.contains("admin")
Match.containsAll("read", "write")
Match.startsWith(1, 2)
Match.endsWith(9, 10)

Match.hasPrefix("user-")
Match.hasSuffix(".json")
Match.containsSubstring("purchase")
Match.equalsIgnoringCase("READY")
Match.matchesRegex(#"user-\d+"#)
Match.matchesRegex(try Regex(#"^user-(\d+)$"#))
```

#### Compose matchers

```swift
Match.not(Match.equal(0))

Match.allOf(
    Match.greaterThan(0),
    Match.atMost(100)
)

Match.anyOf(
    Match.equal("draft"),
    Match.equal("published")
)

Match.oneOf("small", "medium", "large")
```

Nested matchers remain one positional matcher. This also makes capture and a
constraint compose safely:

```swift
let positiveIDs = ArgumentCaptor<Int>()

stub.when {
    $0.load(
        id: Match.allOf(
            positiveIDs.capture(),
            Match.greaterThan(0)
        )
    )
}.thenReturn(value)
```

Only arguments accepted by the complete `allOf` expression are captured.
``ArgumentCaptor`` exposes `values`, `first`, `last`, `removeAll()`, and `reset()`.

For placeholders used throughout a suite, register one exact-type factory:

```swift
Match.Placeholders.register {
    User(name: "recording-placeholder")
}
```

Explicit `using:` and `returning:` values take precedence over registered
factories, and registered factories take precedence over synthesized values.
See <doc:InspectingInteractions> for the process-wide registry contract.

### Configure consecutive behavior

A bare standalone behavior repeats for every matching call:

```swift
pattern.thenReturn("ready")
pattern.thenThrow(NetworkError.offline)
```

A bare intermediate behavior is one-shot, while the bare trailing behavior
repeats:

```swift
let loads = await loader.when {
    try await $0.load()
}
.thenThrow(URLError(.timedOut))
.thenThrow(URLError(.networkConnectionLost))
.thenReturn(["recovered"])
```

This serves two failures followed by an indefinitely repeating success.

Use `times: Int` for an exact finite run and `times: 1...` for an explicit
unbounded terminal:

```swift
let calls = await loader.when {
    try await $0.load()
}
.thenThrow(URLError(.timedOut), times: 2)
.thenReturn(["offline"], times: 1...)
```

Finite behavior returns a ``StubBehaviorChain`` so another behavior can
follow. An unbounded terminal returns observation-only ``ConfiguredCall``; it
supports typed result and outcome queries, `verify`, `arguments()`, and
`stream()` but deliberately has no behavior methods.

Several return values are shorthand for a chain whose final value repeats:

```swift
pattern.thenReturn("first", "second", "last")
```

Use an inspectable finite queue when no answer should repeat:

```swift
let queue = pattern.thenQueue("first", "second")

#expect(queue.remainingAnswerCount == 2)

_ = service.load()
_ = service.load()

#expect(queue.isExhausted)
queue.assertExhausted()
queue.interactions.verify(2 ... 2)
```

Throwing requirements also support `thenThrowQueue`.

### Compute behavior from the call

`then` receives a typed leading prefix of the requirement's arguments:

```swift
stub.when {
    $0.format(
        name: Match.any(),
        count: Match.any()
    )
}.then { name, count in
    "\(name): \(count)"
}
```

Trailing arguments may be omitted:

```swift
stub.when {
    $0.format(
        name: Match.any(),
        count: Match.any()
    )
}.then { name in
    name.uppercased()
}
```

Computed handlers compose with fixed fallbacks:

```swift
let calls = await loader.when {
    try await $0.load(url: Match.any())
}
.then(times: 2) { (url: URL) in
    try await remote.load(url: url)
}
.thenReturn("offline")
```

When the response depends on the attempt, `thenForEachCall` supplies a
one-based count before the typed arguments:

```swift
await loader.when {
    try await $0.load(url: Match.any())
}.thenForEachCall { attempt, url in
    if attempt < 3 {
        throw URLError(.timedOut)
    }
    return try await remote.load(url: url)
}
```

Each counted behavior owns its own counter. A later counted behavior starts
again at one.

Use `thenEscaping` when the first requirement argument is an escaping closure
that the handler retains:

```swift
let callbacks = CallbackCapture<Result>()

stub.when {
    $0.load(completion: Match.any())
}.thenEscaping { completion in
    callbacks.capture(completion)
}
```

### Control async completion

Async requirements can control both their outcome and when they complete.

#### Delay a fixed outcome

```swift
await loader.when {
    try await $0.load()
}.thenReturn(
    ["ready"],
    after: .milliseconds(200)
)
```

`thenThrow` and `thenDoNothing` accept the same `after:` argument. Pass a
``TestDoubleClock`` through the `using:` overload when the delay itself must be
deterministic.

#### Model a wedged dependency

```swift
let calls = await loader.when {
    try await $0.load()
}.thenNeverReturn()
```

The call never completes, even after cancellation, but it is recorded before
parking and remains verifiable.

#### Complete on cancellation

```swift
await loader.when {
    try await $0.load()
}.thenAwaitCancellation()
```

The bare form throws `CancellationError` for a throwing requirement and returns
from a nonthrowing `Void` requirement. Other shapes use an explicit outcome:

```swift
await stub.when {
    await $0.pendingCount()
}.thenAwaitCancellation(returning: 0)

await loader.when {
    try await $0.load()
}.thenAwaitCancellation(throwing: FeedError.cancelled)
```

#### Inject cancellation after a delay

Use `thenCancel(after:)` when the dependency itself should cancel the calling
task, such as a transport aborting an in-flight operation:

```swift
await loader.when {
    try await $0.load()
}.thenCancel(after: .milliseconds(200))
```

The throwing form cancels the caller and throws `CancellationError`. A
nonthrowing async requirement names the value returned after cancellation:

```swift
await stub.when {
    await $0.pendingCount()
}.thenCancel(after: .milliseconds(200), returning: 0)
```

Pass a ``TestDoubleClock`` with `using:` to advance the cancellation deadline
without real sleeps.

#### Resume the call from the test

```swift
let suspension = await loader.when {
    try await $0.load()
}.thenSuspend()

let task = Task {
    try await loader().load()
}

await suspension.waitForCall(within: .seconds(1))
#expect(viewModel.isLoading)

suspension.interactions.verify()
suspension.resume(returning: ["ready"])

#expect(try await task.value == ["ready"])
```

`resume()`, `resume(returning:)`, and `resume(throwing:)` complete one parked
call in arrival order. See <doc:AsyncBehaviors> for cancellation, multiple
parked calls, and clock-aware timeout behavior.

### Inspect interactions

Reading a pattern's arguments is a pure query:

```swift
let calls: [(String, Int)] = events.arguments()
let eventNames: [String] = events.arguments()
```

The result annotation selects the leading tuple shape. Reading arguments does
not verify calls, consume behavior, advance a chain, or commit captures.

Observe future matching calls without polling:

```swift
let stream: InvocationStream<(String, Int)> = events.stream()
var iterator = stream.makeAsyncIterator()

subject.performWork()

let event = try #require(
    await iterator.next(within: .seconds(1))
)
```

Streams begin after creation. Timeout or task cancellation returns `nil`.

Use `history` when the assertion concerns the whole double:

```swift
#expect(stub.history.callCount == 3)
stub.history.verify(3 ... 3)

print(stub.history)
print(stub.history.timeline)
```

``InteractionHistory`` also exposes `wasCalled`, `forwarded`, `stubbed`, and
`verifyNoMoreInteractions()`. The diagnostic timeline records each
requirement, rendered arguments, dispatch decision, selected registration, and
task priority.

### Verify order

Within one double, `verifyInOrder` checks a relative subsequence:

```swift
stub.verifyInOrder {
    $0.start()
    $0.finish()
}
```

`verifyExactlyInOrder` permits no extra calls:

```swift
stub.verifyExactlyInOrder {
    $0.start()
    $0.finish()
}
```

Across doubles, save patterns and use ``InvocationOrder``:

```swift
let charge = gateway.when {
    $0.charge(amount: Match.equal(42))
}.thenDoNothing()

let purchase = analytics.when {
    $0.track(event: Match.equal("purchase"))
}
purchase.thenDoNothing()

InvocationOrder(exhaustive: true) {
    charge
    purchase
}
```

Without `exhaustive: true`, unrelated calls may appear before, between, or
after the expected sequence. The builder also supports direct invocations,
conditionals, loops, async calls, and terminal ``ConfiguredCall`` values.

### Forward through a spy

Use ``Spy`` when a real implementation should handle calls by default:

```swift
let spy: Spy<any Translator> = .make(
    forwardingTo: LiveTranslator()
)

spy.when {
    $0.translate(Match.equal("greeting"))
}.thenReturn("Howdy")

let translator: any Translator = spy()

#expect(translator.translate("greeting") == "Howdy")
#expect(translator.translate("farewell") == "Goodbye")
```

Both paths are recorded:

```swift
let translations = spy.when {
    $0.translate(Match.any())
}

translations.stubbed.verify()
translations.forwarded.verify()

let forwardedKeys: [String] =
    translations.forwarded.arguments()
```

A registration can explicitly return to the live implementation:

```swift
let calls = spy.when {
    try $0.load()
}
.thenThrow(NetworkError.offline, times: 2)
.thenForward(times: 1...)
```

See <doc:ForwardingSpies> for initializer overrides, getter-effect hints, and
the precise forwarding boundary.

### Double an injected function

Use ``ClosureDouble`` for a synchronous unary function:

```swift
let formatter = ClosureDouble<Int, String>()

let twos = formatter.when(equal: 2)
    .thenReturn("first")
    .thenReturn("later")

formatter.whenAny().then {
    "value-\($0)"
}

let function: (Int) -> String = formatter.function

#expect(function(2) == "first")
#expect(function(2) == "later")
#expect(function(9) == "value-9")

twos.verify(2 ... 2)
```

Choose the double matching the injected function's effects:

| Double | Function type |
| --- | --- |
| ``ClosureDouble`` | `(Input) -> Result` |
| ``ThrowingClosureDouble`` | `(Input) throws -> Result` |
| ``AsyncClosureDouble`` | `(Input) async -> Result` |
| ``AsyncThrowingClosureDouble`` | `(Input) async throws -> Result` |
| ``VoidClosureDouble`` | `() -> Result` |

For example:

```swift
let load = AsyncThrowingClosureDouble<URL, Data>()

let calls = load.whenAny()
    .thenThrow(URLError(.timedOut))
    .then { url async throws in
        try await cache.data(for: url)
    }
    .thenReturn(Data())

let function: (URL) async throws -> Data = load.function
```

Effect-aware patterns expose only behavior valid for their function type.
Closure doubles share behavior chains, argument history, streams, ordering,
async controls, and lifecycle operations with protocol doubles.

### Keep setup strict

At the end of an ordinary test, check both stale setup and surprise calls:

```swift
stub.verifyNoUnusedStubs()
stub.verifyNoMoreInteractions()
```

`verifyNoUnusedStubs()` reports every behavior registration no invocation
selected. `verifyNoMoreInteractions()` reports every call not covered by a
successful verification.

With the `TestDoublesTesting` product, Swift Testing can apply these checks at
teardown:

```swift
import TestDoubles
import TestDoublesTesting
import Testing

@Test(.testDoubles)
func checkoutUsesItsGateway() throws {
    // Unused registrations are reported automatically.
}
```

Full strictness also requires every call to be verified, every finite queue to
be consumed, every suspension to be resumed, and every callback capture to be
released:

```swift
@Test(.strictTestDoubles)
func checkoutHasNoSurpriseInteractions() throws {
    // ...
}
```

Individual policies are available through
`testDoubles(strictness:)`. The `TestDoublesTesting` product's documentation
covers the complete option set and task-inheritance behavior.

### Reset between cases

Manage behavior and calls independently:

```swift
stub.clearRecordedInvocations()   // Keep behavior and chain position.
stub.clearConfiguredBehaviors()   // Keep the call history.
stub.reset()                      // Clear both.
```

Clearing a ``Spy``'s behavior returns it to pure forwarding. Calls already
parked by a suspending behavior remain parked because their behavior began
before the clear.

### Choose the right construction path

- Use ``Stub`` for a runtime-generated configurable protocol value.
- Use ``Spy`` when a real implementation should remain the default.
- Use ``Dummy`` when the exercised path must not touch a protocol, concrete
  value, or function dependency.
- Use ``CompiledStub`` when the runtime trampoline cannot represent the
  requirement or cannot run on the platform.
- Use a closure double when an injected function needs behavior or interaction
  verification; use ``Dummy`` when it must remain unused.

The fail-fast factories are convenient when construction failure is a test
configuration error:

```swift
let service: any Service = Stub.make {
    $0.when { $0.value() }.thenReturn("fixture")
}

let unused: any Service = Dummy.make()

let spy: Spy<any Service> = .make(
    forwardingTo: liveService
)
```

Use the throwing initializers when the caller needs to recover:

```swift
let stub = try Stub<any Service>()
let dummy = try Dummy<any Service>()
let spy = try Spy<any Service>(
    forwardingTo: liveService
)
```

When automatic signature discovery is unavailable, prefer
``Stub/Requirement`` factories using `signatureOf:` member references. Use
getter-effect hints for an ordinary throwing getter, and caller-supplied
associated-type bindings for the documented covariant-result slice. The
complete decision tree and explicit schema examples are in
<doc:ConstructionGuide>.

Runtime-generated doubles require executable trampoline support. Use
<doc:ManualStubbing> on physical Apple devices, WASI, or for a requirement
outside the runtime boundary. The normative support and failure contract is
<doc:StubContract>.

### Next steps

- <doc:GettingStarted> covers properties, subscripts, associated types,
  initializers, static requirements, and dynamic `Self`.
- <doc:AsyncBehaviors> covers delays, wedged calls, cancellation, and
  test-controlled completion.
- <doc:InspectingInteractions> covers typed arguments, future-call streams,
  whole-double history, cross-double order, placeholders, and reset.
- <doc:ForwardingSpies> covers forwarding behavior and limitations.
- <doc:RecordAndReplay> captures real results into versioned fixtures.
- <doc:ReusableScenarios> packages named, composable setup.
- <doc:ManualStubbing> provides the portable and language-feature escape hatch.

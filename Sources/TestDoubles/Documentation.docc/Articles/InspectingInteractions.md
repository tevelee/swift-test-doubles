# Inspecting Interactions

Read recorded calls as typed values, order interactions across several doubles,
catch stale setup, register recording placeholders once, and reset a double
between cases.

## Overview

`verify` answers "did this happen, the right number of times?" These tools cover
the questions around it: what exactly were the arguments, in what order did
calls across different doubles happen, which registrations were never used, and
how to reuse a double across parameterized cases. They all read or manage the
same invocation log that `verify` consults, so they compose with the matching
and verification vocabulary from <doc:GettingStarted>. The examples use:

```swift
protocol Analytics: Sendable {
    func track(event: String, value: Int)
}
```

### Read recorded arguments as typed values

When an assertion is more naturally expressed over the recorded arguments than
as a count, save the ``CallPattern`` returned by `when` and call
``CallPattern/arguments()``. It returns typed tuples in call order. The result
annotation selects the tuple shape, and components bind to the requirement's
arguments from the front:

```swift
let stub = try Stub<any Analytics>()
let allEvents = stub.when {
    $0.track(event: Match.any(), value: Match.any())
}
allEvents.thenDoNothing()

let analytics: any Analytics = stub()
analytics.track(event: "add_to_cart", value: 30)
analytics.track(event: "purchase", value: 42)

let calls: [(String, Int)] = allEvents.arguments()
#expect(calls == [("add_to_cart", 30), ("purchase", 42)])
```

Trailing arguments may be omitted, so a narrower tuple reads a leading prefix,
and matchers filter which calls are included:

```swift
let events: [String] = allEvents.arguments()
#expect(events == ["add_to_cart", "purchase"])

let largeEvents = stub.when {
    $0.track(event: Match.any(), value: Match.greaterThan(40))
}
let large: [(String, Int)] = largeEvents.arguments()
#expect(large == [("purchase", 42)])
```

### Observe future interactions as they happen

``InvocationStream`` lets a test await the next matching call without polling
or guessing at a delay. It begins after the stream is created, so setup calls
do not replay into the observation:

```swift
let events: InvocationStream<(String, Int)> = allEvents.stream()

analytics.track(event: "feed_refreshed", value: 1)
var iterator = events.makeAsyncIterator()
let call = try #require(await iterator.next(within: .seconds(1)))

#expect(call.0 == "feed_refreshed")
#expect(call.1 == 1)
```

The pattern's matchers determine which calls the stream observes. Reading it
does not mark a call verified or commit captures. A timed `next` returns `nil`
when its timeout expires; its clock-aware overload accepts ``TestDoubleClock``.
Cancelling a task awaiting `next()` also returns `nil` and removes its waiter
immediately. In a `.strictTestDoubles` scope, matching calls left unread are
reported at teardown; cancelling the awaiting task intentionally ends the
stream and suppresses that check.

### Inspect returned values, errors, and pending calls

A saved ``CallPattern`` retains its result type, so
``CallPattern/results()``, ``CallPattern/errors()``, and
``CallPattern/outcomes()`` expose what matching calls did after they entered
the double:

```swift
let load = stub.when { try await $0.load(id: Match.any()) }
load.then { id in
    if id < 0 { throw LoadError.invalidID }
    return "item-\(id)"
}

_ = try await loader.load(id: 1)
_ = try? await loader.load(id: -1)

#expect(load.results() == ["item-1"])
#expect(load.errors(ofType: LoadError.self) == [.invalidID])

if case .threw(let error) = load.lastOutcome {
    #expect(error is LoadError)
}
```

``InvocationOutcome`` preserves invocation-entry order and distinguishes
returned values, thrown errors, and calls whose async handlers are still
pending. A completed spy delegation is represented by `.forwarded`, because
the ABI transport owns its result and cannot safely type-erase every result
shape. Likewise, a runtime value that cannot be represented by the pattern's
generic result is `.unavailable`; this principally covers dependent dynamic
`Self` results. Yielding `_read` and `_modify` accessors also report
`.unavailable`: retaining their borrowed result beyond coroutine resume would
violate the accessor's ownership boundary.

Ordinary terminal behaviors return ``ConfiguredCall``, which retains the
result generic so `results()`, `outcomes()`, and `lastOutcome` need no type
annotation. Its `interactions` property explicitly erases that generic to
``CallInteractions`` for heterogeneous storage and adapter boundaries.
Initializer and dynamic-`Self` builders remain erased because those results
cannot be represented by one ordinary static result type.

Each pattern and terminal handle also exposes `timings()`. Its
``InvocationTiming`` values use a monotonic `ContinuousClock` instant for
entry and completion, plus a derived `Duration`. Pending calls have no
completion instant or duration. The same fields appear on
``InteractionTimeline/Event`` for whole-double traces.

To synchronize with asynchronous handlers without polling, use
`await interactions.waitForCompletion(count:within:)`. It resumes when at
least the requested number of matching calls have returned, thrown, or
finished forwarding. A timeout reports a test issue and waiting does not mark
the calls as verified.

Entry order and completion order are tracked independently. ``InvocationOrder``
continues to verify when calls entered their doubles; ``CompletionOrder``
verifies when their handlers returned, threw, or finished forwarding:

```swift
InvocationOrder {
    slowLoad
    fastLoad
}
CompletionOrder {
    fastLoad
    slowLoad
}
```

`history.completionTimeline` presents the same whole-double log sorted by its
process-global completion sequence. Calls that remain pending appear last.

Call-stack capture is opt-in because symbolization is comparatively expensive:

```swift
let stub = try Stub<any Analytics>()
    .captureCallStacks(maxFrames: 16)
```

Subsequent timeline events expose the capped symbols through `callStack`.
`CompiledStub`, saved call patterns, and terminal interaction handles provide the
same opt-in method; enabling it through a pattern applies to its whole double.
WASI has no thread stack-symbolization API, so capture is a no-op on that
platform.

### Inspect the whole double

When a `verify` fails, the useful next question is what actually *did* get
called. ``InteractionHistory`` brings whole-double counts, range verification,
spy dispatch filtering, and diagnostics under `history`:

```swift
#expect(stub.history.callCount == 2)
stub.history.verify(2 ... 2)
print(stub.history.timeline)

spy.history.forwarded.verify(1...)
spy.history.stubbed.verify()
```

Each `history` access is an immutable random-access collection snapshot whose
elements are ``InteractionTimeline/Event`` values. Save one when several
assertions must describe the same moment, or fetch `history` again to include
new calls:

```swift
let snapshot = stub.history
let failures = snapshot.filter(\.didThrow)
let slowCalls = snapshot.filter { ($0.duration ?? .zero) > .milliseconds(100) }
```

An event's coarse `outcome` distinguishes pending, returned, thrown,
forwarded, and unavailable results without retaining user values or errors.

Its `description` is a human-readable, ordered log of every invocation — one
call per line, with arguments woven back into the requirement's labels — so a
call reads the way it was written:

```swift
analytics.track(event: "add_to_cart", value: 30)
analytics.track(event: "purchase", value: 42)

print(stub.history)
// [TestDoubles] Recorded 2 interactions in order:
//   #1  track(event: "add_to_cart", value: 30)
//   #2  track(event: "purchase", value: 42)
```

Reading count, description, or timeline is a pure query: it does not verify,
consume behavior, or commit captures. Successful `history.verify` marks every
call in that view for `verifyNoMoreInteractions()`. The older
`describeInteractions()` and `interactionTimeline()` methods remain equivalent
diagnostic conveniences.

Reading arguments is a pure query. Unlike `verify`, it does not report an
issue on a mismatch, consume configured behavior, advance a chain, or commit
captures, so it is safe to call as often as needed. It is the right tool for
custom assertions; keep `verify` and `verifyInOrder` when a count or order is
the expectation and their diagnostics add value. The same ``CallPattern`` API
is available from ``Stub``, ``Spy``, and ``CompiledStub``.

### Order interactions across doubles

`verifyInOrder` checks a subsequence within a single double.
``InvocationOrder`` extends that to interactions spanning any number of doubles,
which is how you assert that a payment was charged *before* the analytics event
fired when each lives on its own stub:

```swift
let gateway = try Stub<any PaymentGateway>()
let analytics = try Stub<any Analytics>()
let charge = gateway.when {
    $0.charge(amount: Match.equal(42))
}
charge.thenDoNothing()
let purchase = analytics.when {
    $0.track(event: Match.equal("purchase"), value: Match.any())
}.thenDoNothing()

Checkout(gateway: gateway(), analytics: analytics()).placeOrder()

InvocationOrder(exhaustive: true) {
    gateway().charge(amount: 42)
    analytics().track(event: "purchase", value: 42)
}
```

Each builder expression matches the earliest recorded call after the previous
one and advances a shared cursor there. Calls in the builder run in capture
mode, so they do not record additional interactions or consume behavior.
`exhaustive: true` additionally requires every interaction on each participating
double to appear in the sequence. Omit the flag for subsequence verification,
where unrelated calls may appear before, between, or after the listed
expectations, just as with `verifyInOrder`. Ordering is by a process-wide
sequence stamped on every recorded call, so it holds across `Stub`, `Spy`, and
`CompiledStub`, and across sync and async requirements. A step that finds no later
matching call reports a test issue at its own source location and leaves the
cursor unchanged; successful steps commit their captors.

Both a ``CallPattern`` saved directly from `when` and the ``ConfiguredCall``
returned by an ordinary terminal `then` method can be listed directly instead
of repeating a call. Erased ``CallInteractions`` handles work as well. This is
useful when the same description also configures behavior, reads arguments, or
uses rich matchers:

```swift
InvocationOrder(exhaustive: true) {
    charge
    purchase
}
```

Conditionals and loops are supported. Async and throwing invocations use the
ordinary `await` and `try` spellings. Like `when` and `verify`, a direct
invocation whose return type has no safe recording placeholder needs a factory
registered with ``Match/Placeholders``; saving a pattern through the
`returning:` overload is the explicit alternative.

`InvocationOrder` has its own ``InvocationOrder/verifyNoMoreInteractions(fileID:filePath:line:column:)``,
which remains the explicit strict terminator for the older fluent chain. It
reports the same per-double diagnostic as `Stub.verifyNoMoreInteractions()` and
`CompiledStub.verifyNoMoreInteractions()`, for every double this session verified
at least once. A double the session never touched is out of scope, even if it
has recorded calls of its own — check that one directly.

### Catch stale and unreachable registrations

`verifyNoUnusedStubs()` reports every `when` registration that no recorded call
ever matched. This catches setup that has drifted out of sync with the code, and
more subtly, a specific registration left unreachable behind an earlier
catch-all under first-match-wins ordering:

```swift
let stub = try Stub<any Analytics>()
// Registered in the wrong order: the catch-all answers every call, so the
// specific registration below it can never match.
stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenReturn(())
stub.when { $0.track(event: Match.equal("purchase"), value: Match.any()) }.thenReturn(())

stub().track(event: "purchase", value: 42)

stub.verifyNoUnusedStubs()   // reports the shadowed "purchase" registration
```

Call it at the end of a test to keep registrations honest. It reads the same
consumption tracking the matcher engine already maintains, so it costs nothing
during the test itself.

A shadowed registration is also caught eagerly: when a new `when` is provably
unreachable behind an earlier one, an issue is reported at that `when` site as
you register it, without waiting for `verifyNoUnusedStubs()`. The check is
sound, flagging only registrations proven unreachable (a universal earlier
matcher such as `Match.any()`, or the identical accepted set at every argument
position) and never guessing through opaque predicates, so correct
specific-before-broad ordering is never flagged.

### Scope recording placeholders to a test

The recording pass behind every `when` and one-shot `verify` closure
needs one valid temporary value per argument and result. TestDoubles synthesizes
these for most value types, but class instances and existentials normally take a
value at each site through the `using:` and `returning:` overloads.
``Match/Placeholders`` can supply that value lexically for one test:

```swift
protocol Directory {
    func displayName(for user: User) -> String   // User is a class
}

try Match.Placeholders.withFactory({ User(name: "placeholder") }) {
    let stub = try Stub<any Directory>()
    // No Match.any(using:) needed inside this task-local scope.
    stub.when { $0.displayName(for: Match.any()) }.thenReturn("Blob")
}
```

A factory value is used only while recording; it is never matched against,
returned from a stubbed call, or retained past the recording pass. Structured
child tasks inherit the scope and detached tasks do not. Nested scopes may
override one exact type while retaining factories for other types. Precedence
is explicit `using:`/`returning:` values first, then task-scoped factories,
process-global registrations, and synthesized values.

``Match/Placeholders/register(_:_:)`` remains available for suite-wide setup.
Its registry is process-global, so prefer ``Match/Placeholders/withFactory(_:operation:)``
inside individual or parallel tests, and unregister suite defaults when they
are no longer needed.

### Reset a double between cases

`clearRecordedInvocations()` clears the invocation log while preserving
configured behavior. Two more tools complete the picture.
`clearConfiguredBehaviors()` removes every `when` registration while preserving
the log, which returns a ``Spy`` to pure forwarding and lets a test replace a
registration that first-match-wins would otherwise shadow:

```swift
stub.clearConfiguredBehaviors()
stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenReturn(())  // fresh
```

`reset()` on ``Stub``, ``Spy``, and ``CompiledStub`` does both at once, restoring
the just-constructed state so one double can be reconfigured from scratch
across parameterized cases:

```swift
for scenario in scenarios {
    stub.reset()
    stub.when { $0.track(event: Match.any(), value: Match.any()) }.thenDoNothing()
    // exercise `scenario` against a clean double
}
```

In a ``ManualStubConformer``, forward a protocol requirement named `reset`
through `stub.requirements.reset()` so it does not collide with the controller's
`stub.reset()` operation. Calls already parked by a suspending behavior are
unaffected by either clear; their behavior started before it ran.

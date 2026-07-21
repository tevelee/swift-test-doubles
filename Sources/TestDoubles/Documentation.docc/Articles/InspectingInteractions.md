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
as a count, ``Stub/invocations(_:)`` returns them as typed tuples in call order.
The result annotation selects the tuple shape, and components bind to the
requirement's arguments from the front:

```swift
let stub = try Stub<any Analytics>()
stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()

let analytics: any Analytics = stub()
analytics.track(event: "add_to_cart", value: 30)
analytics.track(event: "purchase", value: 42)

let calls: [(String, Int)] = stub.invocations {
    $0.track(event: any(), value: any())
}
#expect(calls == [("add_to_cart", 30), ("purchase", 42)])
```

Trailing arguments may be omitted, so a narrower tuple reads a leading prefix,
and matchers filter which calls are included:

```swift
let events: [String] = stub.invocations { $0.track(event: any(), value: any()) }
#expect(events == ["add_to_cart", "purchase"])

let large: [(String, Int)] = stub.invocations {
    $0.track(event: any(), value: greaterThan(40))
}
#expect(large == [("purchase", 42)])
```

Reading invocations is a pure query. Unlike `verify`, it does not report an
issue on a mismatch, consume configured behavior, advance a chain, or commit
captors, so it is safe to call as often as needed. It is the right tool for
custom assertions; keep `verify` and `verifyInOrder` when a count or order is
the expectation and their diagnostics add value. The same API is available on
``Spy`` and ``ManualStub``, with `returning:` overloads for results that need a
recording placeholder.

### Order interactions across doubles

`verifyInOrder` checks a subsequence within a single double.
``InvocationOrder`` extends that to interactions spanning any number of doubles,
which is how you assert that a payment was charged *before* the analytics event
fired when each lives on its own stub:

```swift
let gateway = try Stub<any PaymentGateway>()
let analytics = try Stub<any Analytics>()
gateway.when { $0.charge(amount: any()) }.thenDoNothing()
analytics.when { $0.track(event: any(), value: any()) }.thenDoNothing()

Checkout(gateway: gateway(), analytics: analytics()).placeOrder()

let order = InvocationOrder()
order.verify(gateway) { $0.charge(amount: equal(42)) }
order.verify(analytics) { $0.track(event: equal("purchase"), value: any()) }
```

Each `verify(_:_:)` step matches the earliest recorded call after the
previously verified one and advances a
shared cursor there. Unrelated calls may appear between the verified ones, just
as with `verifyInOrder`. Ordering is by a process-wide sequence stamped on every
recorded call, so it holds across `Stub`, `Spy`, and `ManualStub`, and across
sync and async requirements. A step that finds no later matching call reports a
test issue at its own source location and leaves the cursor unchanged;
successful steps commit their captors and count toward
`verifyNoMoreInteractions()`.

### Catch stale and unreachable registrations

`verifyNoUnusedStubs()` reports every `when` registration that no recorded call
ever matched. This catches setup that has drifted out of sync with the code, and
more subtly, a specific registration left unreachable behind an earlier
catch-all under first-match-wins ordering:

```swift
let stub = try Stub<any Analytics>()
// Registered in the wrong order: the catch-all answers every call, so the
// specific registration below it can never match.
stub.when { $0.track(event: any(), value: any()) }.thenReturn(())
stub.when { $0.track(event: equal("purchase"), value: any()) }.thenReturn(())

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
matcher such as `any()`, or the identical accepted set at every argument
position) and never guessing through opaque predicates, so correct
specific-before-broad ordering is never flagged.

### Register recording placeholders once

The recording pass behind every `when`, `verify`, and `invocations` closure
needs one valid temporary value per argument and result. TestDoubles synthesizes
these for most value types, but class instances and existentials normally take a
value at each site through the `using:` and `returning:` overloads.
``RecordingPlaceholders`` supplies that value once for a whole suite instead:

```swift
protocol Directory {
    func displayName(for user: User) -> String   // User is a class
}

RecordingPlaceholders.register { User(name: "placeholder") }

let stub = try Stub<any Directory>()
// No any(using:) needed: the registered factory supplies the recording value.
stub.when { $0.displayName(for: any()) }.thenReturn("Blob")
```

A registered value is used only while recording; it is never matched against,
returned from a stubbed call, or retained past the recording pass. Precedence is
explicit `using:`/`returning:` values first, then registered factories, then
synthesized values, so a registration is a default that per-call values still
override. Factories match the exact registered type, so an existential and each
concrete class register separately. The registry is process-wide: register in
suite setup, or ``RecordingPlaceholders/unregister(_:)`` on the way out, rather
than registering inside individual parallel tests.

### Reset a double between cases

`clearRecordedInvocations()` clears the invocation log while preserving
configured behavior. Two more tools complete the picture.
`clearConfiguredBehaviors()` removes every `when` registration while preserving
the log, which returns a ``Spy`` to pure forwarding and lets a test replace a
registration that first-match-wins would otherwise shadow:

```swift
stub.clearConfiguredBehaviors()
stub.when { $0.track(event: any(), value: any()) }.thenReturn(())  // fresh
```

`reset()` on ``Stub`` and ``Spy`` does both at once, restoring the
just-constructed state so one double can be reconfigured from scratch across
parameterized cases:

```swift
for scenario in scenarios {
    stub.reset()
    stub.when { $0.track(event: any(), value: any()) }.thenDoNothing()
    // exercise `scenario` against a clean double
}
```

``ManualStub`` has `clearConfiguredBehaviors()` but deliberately no `reset()`:
its member names dispatch protocol requirements, so a concrete `reset` method
would shadow a protocol's own `reset` requirement. Pair
`clearConfiguredBehaviors()` with `clearRecordedInvocations()` there for the same
effect. Calls already parked by a suspending behavior are unaffected by either
clear; their behavior started before it ran.

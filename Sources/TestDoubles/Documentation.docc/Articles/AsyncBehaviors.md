# Async Behaviors

Drive loading states, latency, timeouts, and cancellation deterministically by
controlling when an async requirement completes, not just what it returns.

## Overview

A real async dependency completes on its own schedule, and the interesting
moments are often *before* it does: the loading spinner that should show while a
request is in flight, the timeout that should fire when it never answers, the
cancellation that should propagate when the caller gives up. These are hard to
reproduce against a live dependency and easy to get wrong with `Task.sleep`,
which trades determinism for wall-clock time.

TestDoubles configures the *timing* of an async completion with the same
`when`/`then` vocabulary used for values. Four behaviors cover the common
shapes:

| Behavior | Completes | Use for |
| --- | --- | --- |
| `thenReturn(_:after:)` / `thenThrow(_:after:)` / `thenDoNothing(after:)` | After a delay | Latency, ordering against other work |
| ``StubBuilder/thenNeverReturn()`` | Never | Timeout and hedging paths |
| ``StubBuilder/thenAwaitCancellation()`` | On task cancellation | Cancellation propagation |
| ``StubBuilder/thenSuspend()`` | When the test resumes it | Loading states, precise in-flight assertions |

Every one of these requires an async requirement. Configuring a delay or a park
on a synchronous requirement, which has nowhere to suspend, fails with a
diagnostic at the `when` site rather than at the eventual call. The examples
below use one protocol:

```swift
protocol FeedService: Sendable {
    func loadFeed() async throws -> [String]
    func refresh() async
}
```

### Deliver a result after a delay

Add `after:` to any fixed behavior to hold the call open for that duration
before completing. This works on `thenReturn(_:after:)`,
`thenThrow(_:after:)`, and `thenDoNothing(after:)`, standalone or inside a
chain:

```swift
let stub = try Stub<any FeedService>()
await stub.when { try await $0.loadFeed() }
    .thenReturn(["Hello, world"], after: .milliseconds(200))

let feed = FeedViewModel(service: stub())
async let posts = feed.refreshedPosts()

// The call is still in flight here, so the view model is loading.
#expect(feed.isLoading)
#expect(try await posts == ["Hello, world"])
#expect(feed.isLoading == false)
```

The delay uses a `ContinuousClock`, so it is measured in elapsed time. During
the delay a *throwing* requirement observes task cancellation and rethrows it,
so a cancelled `loadFeed()` fails fast with a `CancellationError` instead of
waiting out the full duration. A *non-throwing* requirement has no error channel
to carry cancellation, so its delay always runs to completion.

Delays compose with behavior chains and repeat counts. This models a dependency
that is slow twice, then recovers instantly:

```swift
await stub.when { try await $0.loadFeed() }
    .thenThrow(URLError(.timedOut), after: .milliseconds(100), times: 2)
    .thenReturn(["recovered"])
```

### Model a wedged dependency

``StubBuilder/thenNeverReturn()`` parks every matching call and never completes
it, which is exactly what a hung network connection or a deadlocked service
looks like from the caller's side. Use it to exercise the timeout path that
should win the race:

```swift
let stub = try Stub<any FeedService>()
await stub.when { try await $0.loadFeed() }.thenNeverReturn()

let feed = FeedViewModel(service: stub())
let result = await feed.refreshWithTimeout(.milliseconds(200))
#expect(result == .timedOut)
```

A parked call stays suspended even if its task is cancelled; reacting to
cancellation is ``StubBuilder/thenAwaitCancellation()``'s job, not this one.
Because the call never returns, drive it from a task the test does not `await`,
or from code under test that races it against a timeout. The invocation is
recorded before the call parks, so verification, including
`verify(_:within:)`, observes calls that never complete:

```swift
await stub.verify(1..., within: .seconds(1)) { try await $0.loadFeed() }
```

### Test cancellation propagation

``StubBuilder/thenAwaitCancellation()`` parks a matching call until its task is
cancelled, then completes it the way a well-behaved dependency would. The bare
form derives its outcome from the requirement's shape: a throwing requirement
throws `CancellationError`, and a non-throwing `Void` requirement returns.

```swift
let stub = try Stub<any FeedService>()
await stub.when { try await $0.loadFeed() }.thenAwaitCancellation()

let task = Task { try await stub().loadFeed() }
await stub.verify(1..., within: .seconds(1)) { try await $0.loadFeed() }
task.cancel()

await #expect(throws: CancellationError.self) { try await task.value }
```

When the dependency should complete with a specific outcome on cancellation
rather than the implicit one, name it. Use
``StubBuilder/thenAwaitCancellation(returning:)`` for a value or
``StubBuilder/thenAwaitCancellation(throwing:)`` for an error:

```swift
await stub.when { await $0.pendingCount() }.thenAwaitCancellation(returning: 0)
await stub.when { try await $0.loadFeed() }
    .thenAwaitCancellation(throwing: FeedError.cancelled)
```

A task that is already cancelled when the call arrives completes immediately.
The bare form is only available where an implicit outcome exists; a non-throwing
requirement that returns a value has none, so it must use the `returning:` form,
and the bare call fails with a diagnostic pointing there.

### Control completion from the test

``StubBuilder/thenSuspend()`` is the most precise tool: it parks matching calls
and hands the test a ``StubSuspension`` handle that decides exactly when, and
how, each one completes. This turns "assert the loading state, then let the call
finish, then assert the result" into a straight-line, sleep-free test:

```swift
let stub = try Stub<any FeedService>()
let suspension = await stub.when { try await $0.loadFeed() }.thenSuspend()

let feed = FeedViewModel(service: stub())
let refresh = Task { await feed.refresh() }

await suspension.waitForCall()   // the call has arrived and parked
#expect(feed.isLoading)

suspension.resume(returning: ["Hello, world"])
await refresh.value
#expect(feed.isLoading == false)
#expect(feed.posts == ["Hello, world"])
```

``StubSuspension/waitForCall(count:)`` suspends until at least `count` matching
calls are currently parked, returning immediately when they already are. Resume
completes the oldest parked call, one per call, in arrival order:
``StubSuspension/resume(returning:)`` delivers a value,
``StubSuspension/resume(throwing:)`` throws an error, and
``StubSuspension/resume()`` completes a parked `Void` call. Resumed calls leave
the parked set, so `count` describes calls in flight now, not a running total.

Because the handle is the only thing that completes a parked call, ordering is
under the test's control. This drives two concurrent requests to resolve in a
deliberate order:

```swift
let suspension = await stub.when { try await $0.loadFeed() }.thenSuspend()
let first = Task { try await stub().loadFeed() }
await suspension.waitForCall()
let second = Task { try await stub().loadFeed() }
await suspension.waitForCall(count: 2)

suspension.resume(returning: ["first"])
suspension.resume(returning: ["second"])
#expect(try await first.value == ["first"])
#expect(try await second.value == ["second"])
```

Resuming when no call is parked is a test bug and halts with a diagnostic;
`await waitForCall()` first so the call has arrived. Throwing into a
non-throwing requirement likewise fails with a diagnostic.

### Choosing among the four

- Reach for **`after:`** when only the latency matters and the result is fixed.
- Reach for **`thenNeverReturn()`** when the point is that the call *doesn't*
  finish, and something else, a timeout or a hedge, should win.
- Reach for **`thenAwaitCancellation()`** when the test is specifically about
  cancellation reaching the dependency.
- Reach for **`thenSuspend()`** when the test needs to assert state while the
  call is in flight, or to sequence several in-flight calls precisely.

All four are terminal behaviors: like an unbounded `thenReturn`, nothing chains
after them, though each can itself terminate a chain that begins with other
behaviors. They compose with matchers, so different arguments can suspend,
delay, or complete differently. And they preserve the async handler contract
from <doc:GettingStarted>: a resumed or delayed completion runs on the calling
task, preserving its task-local values, cancellation state, priority, and
executor.

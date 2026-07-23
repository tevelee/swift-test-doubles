# Recording and Replaying Interactions

Turn a `Spy`'s forwarding boundary into a record-once, replay-everywhere
fixture for a real dependency.

## Overview

`Spy` already forwards unmatched calls to a real implementation. Recording
captures what that real dependency returned, so a later test can replay it
without the dependency being reachable, fast, or deterministic:

```swift
let live = LiveWeatherService()
let spy: Spy<any WeatherService> = .make(forwardingTo: live)
let session = RecordingSession()

spy.when { try await $0.currentConditions(for: any()) }
    .thenRecord(as: "currentConditions", into: session) { city in
        try await live.currentConditions(for: city)
    }

let service: any WeatherService = spy()
_ = try await service.currentConditions(for: "Berlin")

try session.save(to: fixtureURL)
```

`thenRecord(as:into:calling:)` runs `handler` — typically a direct call to the
real dependency the spy wraps — and records its result into the session under
`key`, in addition to returning it as this call's answer like `then` would.
Only a successful result is captured; a thrown error still propagates to the
caller but is not recorded.

## Replaying a fixture

Load the persisted fixture and replay it on a plain `Stub`, with no real
dependency involved:

```swift
let fixture = try InteractionFixture.load(from: fixtureURL)
let stub = try Stub<any WeatherService>()

stub.when { try await $0.currentConditions(for: any()) }
    .thenReplay(as: "currentConditions", from: fixture)

let service: any WeatherService = stub()
try await service.currentConditions(for: "Berlin") // the recorded value
stub.verify { try await $0.currentConditions(for: equal("Berlin")) }
```

`thenReplay(as:from:)` configures fixed responses from the fixture's calls
recorded under `key`, in recording order — exactly like a `thenReturn(_:_:_:)`
chain built from playback: the last recorded response repeats for every call
after that. `key` must match the one recording used and have at least one
recorded call, or this halts with a diagnostic naming the missing key.

## Working without a file

`RecordingSession/snapshot()` freezes the calls recorded so far into an
in-memory ``InteractionFixture`` — useful for record-and-replay within one
test run, without touching disk. Persisting a fixture is only necessary to
share it across test runs or commit it alongside the test that recorded it.

## Constraints

Both sides need the requirement's result type to round-trip through
`JSONEncoder`/`JSONDecoder`: `thenRecord` requires `Result: Encodable &
Sendable`, and `thenReplay` requires `Result: Decodable`. A result that fails
to encode or decode halts with a diagnostic naming the key and type, rather
than silently dropping or misreporting the recorded value.

A session accepts concurrent recordings safely, so `thenRecord` may be
attached to a requirement invoked from multiple tasks during the same
recording pass.

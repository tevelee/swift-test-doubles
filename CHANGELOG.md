# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Eager detection of unreachable stub registrations. When a new `when`
  registration is provably shadowed by an earlier one under first-match-wins,
  such as a specific matcher registered behind an earlier catch-all, an issue
  is reported at that `when` site instead of silently never firing. The check
  is sound: it flags only registrations proven unreachable (a universal
  earlier matcher, or the identical accepted set at every position) and never
  guesses through opaque predicates.
- Delayed delivery for fixed behaviors on async requirements: every
  `thenReturn`, `thenThrow`, and `thenDoNothing` overload takes an
  `after: Duration` that suspends the matching call for that long before
  completing, including inside behavior chains, so tests can drive loading
  states and retry timing against realistic latency. During the delay a
  throwing requirement observes task cancellation and rethrows it; a
  non-throwing requirement's delay always runs to completion. Registering a
  delay on a synchronous requirement fails with a diagnostic.
- `thenNeverReturn()` parks every matching async invocation without ever
  completing it, modeling a wedged dependency for timeout and hedging paths.
  Parked calls ignore cancellation, stay observable through verification, and
  the behavior can terminate a chain, such as failing once and then hanging.
  Registering it on a synchronous requirement fails with a diagnostic.
- `thenAwaitCancellation()` parks every matching async invocation until its
  task is cancelled, then completes it the way a well-behaved dependency
  would: a throwing requirement throws `CancellationError` and a non-throwing
  `Void` requirement returns. The `returning:` and `throwing:` forms name an
  explicit post-cancellation outcome, an already-cancelled task completes
  immediately, parked calls stay observable through verification, and the
  behavior can terminate a chain. Registering it on a synchronous
  requirement, or the bare form where no implicit outcome exists, fails with
  a diagnostic.
- `thenSuspend()` parks matching async invocations and returns a
  `StubSuspension` handle the test drives: `waitForCall(count:)` awaits a
  call's arrival deterministically, and `resume(returning:)`,
  `resume(throwing:)`, or the `Void` shorthand `resume()` completes parked
  calls in arrival order. This makes loading states, in-flight assertions,
  and race ordering testable without sleeps. Resuming with no call parked,
  registering on a synchronous requirement, or throwing into a non-throwing
  requirement each fail with a diagnostic.
- Typed invocation access on `Stub`, `Spy`, and `ManualStub`: `invocations`
  returns the recorded arguments of matching calls as typed tuples in call
  order, with the tuple shape selected by the result annotation, such as
  `let events: [(String, Int)] = analytics.invocations { $0.track(event:
  any(), value: any()) }`. Components bind to the requirement's arguments
  from the front, matchers filter which calls are included, and reading is a
  pure query that neither verifies, consumes configured behavior, nor
  commits captors. `returning:` overloads cover results that need a valid
  recording placeholder.
- `clearConfiguredBehaviors()` removes every `when` registration while
  preserving the invocation log, returning a `Spy` to pure forwarding, and
  `reset()` on `Stub` and `Spy` restores the just-constructed state by
  clearing behaviors and invocations together. `ManualStub` gets
  `clearConfiguredBehaviors()` but deliberately no `reset()`, since member
  names dispatch requirements there and a concrete `reset` would shadow a
  protocol's own `reset` requirement.
- `thenForward()` on `Spy` registrations explicitly forwards matching calls
  to the real target. At the end of a chain it hands remaining calls back to
  the live implementation, such as failing twice and then recovering for
  real; standalone, registered before a broader override, it punches a hole
  through it under first-match-wins. Forwarded calls stay recorded and
  verifiable. Registering it on a double without a forwarding target fails
  with a diagnostic.
- `InvocationOrder` verifies interaction order across any number of doubles:
  each `verify(stub) { ... }` step matches the earliest recorded invocation
  after the previously verified one and advances a shared cursor, with
  unrelated calls allowed in between, like `verifyInOrder` on a single
  double. Works across `Stub`, `Spy`, and `ManualStub`, sync and async. A
  failed step reports a test issue at its own call site; successful steps
  commit captors and count for `verifyNoMoreInteractions()`.
- `verifyNoUnusedStubs()` reports every `when` registration that no recorded
  call ever matched, listing each unused registration's signature. This
  catches stale setup and, more importantly, registrations left unreachable
  behind an earlier catch-all under first-match-wins ordering.
- `RecordingPlaceholders` registers suite-wide factories for recording
  placeholder values, so class and existential arguments and results no
  longer need `using:` or `returning:` at every `when`/`verify` site.
  Explicit `using:`/`returning:` values win over registered factories, and
  registered factories win over synthesized values; registered values are
  used only during the recording pass and are never matched against or
  returned.
- Rich argument matchers that compose on the existing matching engine:
  logical combinators `not`, `allOf`, `anyOf`, and `oneOf`; the equality and
  identity matchers `notEqual` and `identical(to:)`; the comparison matchers
  `greaterThan`, `atLeast`, `lessThan`, `atMost`, and `inRange`; the optional
  matchers `isNil`, `notNil`, and `some`; the collection matchers `isEmpty`,
  `nonEmpty`, `hasCount` (by value or nested matcher), `contains`,
  `contains(where:)`, `containsAll`, `startsWith`, and `endsWith`; and the
  string matchers `hasPrefix`, `hasSuffix`, `containsSubstring`,
  `equalsIgnoringCase`, and `matchesRegex`. Combinators fold nested matchers
  into a single positional matcher, so `allOf(captor.capture(),
  greaterThan(0))` captures only the arguments that satisfy the whole
  expression, and composed matchers keep legible diagnostic descriptions.
- WatchOS simulator support
- Explicit `thenDoNothing()` behavior for `Void`-returning stub requirements;
  `when` now requires a terminal behavior, so ignoring its builder produces a
  compiler warning and no longer installs an implicit `Void` fallback.
- Chainable fixed returns, errors, and no-ops for consecutive matching
  invocations, with the final configured behavior repeating.
- `Spy.make(_:forwardingTo:)` for fail-fast construction of a forwarding spy
  that remains available for stubbing and verification.
- Typed-throws forwarding for `ManualStub` through the explicit
  `throwing:` overloads of `throwingCall` and `asyncThrowingCall`.
- `InvocationOrder.verifyNoMoreInteractions()` reports unverified interactions
  across every double a session has verified at least once, the cross-double
  counterpart to `Stub.verifyNoMoreInteractions()` and
  `ManualStub.verifyNoMoreInteractions()`, so a test using several doubles
  together can close all of them out in one call instead of one per double.
  A double the session never touched is out of scope, even if it recorded
  calls of its own.

### Changed

- The "no matching stub" diagnostic now shows, for each registered stub, which
  argument its matcher accepted or rejected with the actual value against the
  expected matcher, so the closest near-miss is visible at a glance instead of
  only listing the registrations.
- When multiple `when` registrations match a call, the first matching
  registration now wins and matcher specificity no longer ranks
  registrations. Registration order is the entire contract, like the cases of
  a `switch`: register specific matchers first and broad fallbacks last,
  since an earlier registration shadows any later one it overlaps with.
- Recoverable `Stub`, `Dummy`, and `Spy` constructors now declare
  `throws(StubError)`; the corresponding `Stub.make`, `Dummy.make`, and `Spy.make`
  factories remain fail-fast conveniences.
- The `Spy.make` protocol metatype parameter defaults to the contextual type,
  so the existential can come from the result annotation:
  `let spy: Spy<any P> = .make(forwardingTo: live)`. Without an annotation
  or explicit metatype, the forwarding target's concrete type is inferred and
  construction fails fast with a protocol-existential diagnostic. Spy
  construction also accepts flat or declaration-grouped getter-effect hints.
- Fabricated witness identities are retained for process-stable cache identity
  only after successful construction; failed construction releases its
  temporary witness allocations.
- `makeStub`, `makeDummy`, and `makeSpy` are now `Stub.make`, `Dummy.make`, and
  `Spy.make`: static factory methods on the type they construct instead of
  top-level functions, so they surface in autocomplete and documentation
  alongside each type's `init` and support leading-dot construction such as
  `let spy: Spy<any P> = .make(forwardingTo: live)`. The free functions no
  longer exist.

### Fixed

- Constructing a test double for a bound existential composition that needs
  two or more witness tables (for example `any A<Int> & B<String>`) on an OS
  runtime older than the 26.4 releases now fails with a descriptive
  `StubError.unsupportedProtocolShape` instead of crashing. Those runtimes
  miscount witness tables while copying extended existential containers
  (swiftlang/swift#85346), so materializing the double overran memory with a
  `SIGBUS`. Unbound compositions with caller-supplied `associatedTypes:`
  bindings keep working on every supported OS.

## [0.0.1] - 2026-07-18

### Added

- Runtime-generated `Stub` and fail-closed `Dummy` values for supported Swift
  protocol shapes, with no macros or generated conformers.
- Synchronous, throwing, async, typed-throwing, initializer, property,
  subscript, dynamic `Self`, protocol-composition, and bounded
  primary-associated-type support across the documented runtime boundary.
- Fixed, sequenced, and handler-based behavior; argument matching and capture;
  immediate, eventual, ordered, and unverified-interaction checks.
- `ManualStub` for protocols and platforms outside the runtime trampoline's
  supported boundary.
- CI workflows for the documented macOS, Linux, simulator, and Mac Catalyst
  matrix, including watchOS Simulator, release-mode, and x86_64 runtime checks.

### Security

- Runtime and ABI boundaries fail closed when a protocol requirement cannot be
  represented safely.

[Unreleased]: https://github.com/tevelee/swift-test-doubles/commits/main
[0.0.1]: https://github.com/tevelee/swift-test-doubles/tree/0.0.1

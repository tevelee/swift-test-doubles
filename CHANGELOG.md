# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
- `makeSpy(_:forwardingTo:)` for fail-fast construction of a forwarding spy
  that remains available for stubbing and verification.
- Typed-throws forwarding for `ManualStub` through the explicit
  `throwing:` overloads of `throwingCall` and `asyncThrowingCall`.

### Changed

- When multiple `when` registrations match a call, the first matching
  registration now wins and matcher specificity no longer ranks
  registrations. Registration order is the entire contract, like the cases of
  a `switch`: register specific matchers first and broad fallbacks last,
  since an earlier registration shadows any later one it overlaps with.
- Recoverable `Stub`, `Dummy`, and `Spy` constructors now declare
  `throws(StubError)`; the corresponding `makeStub`, `makeDummy`, and `makeSpy`
  factories remain fail-fast conveniences.
- The `makeSpy` protocol metatype parameter defaults to the contextual type,
  so the existential can come from the result annotation:
  `let spy: Spy<any P> = makeSpy(forwardingTo: live)`. Without an annotation
  or explicit metatype, the forwarding target's concrete type is inferred and
  construction fails fast with a protocol-existential diagnostic. Spy
  construction also accepts flat or declaration-grouped getter-effect hints.
- Fabricated witness identities are retained for process-stable cache identity
  only after successful construction; failed construction releases its
  temporary witness allocations.

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

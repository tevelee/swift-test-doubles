# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Typed invocation outcome inspection through `results()`, `errors()`,
  `outcomes()`, and `lastOutcome`, including pending async calls and completed
  spy forwarding.
- Monotonic invocation start/completion timestamps and elapsed durations on
  call patterns, terminal handles, and whole-double timeline events.
- Event-driven `waitForCompletion(count:within:)` synchronization for matching
  interactions, including throwing and forwarded calls.
- Cross-double `CompletionOrder` verification and completion-sorted history
  timelines, independent of invocation-entry order.
- Opt-in, frame-limited call-stack capture on stubs and saved interaction
  handles, exposed through timeline events.
- Independent `beforeEachCall` and `afterEachCall` side-effect hooks that
  compose with returns, errors, suspending handlers, and spy forwarding.
- Delayed caller-cancellation injection through `thenCancel(after:)`, with an
  explicit fallback form for nonthrowing async requirements and manual-clock
  support.
- Deterministic fault injection that fails every Nth call or follows a seeded
  probability sequence while returning an explicit success value otherwise.
- Approximate floating-point matching with combined absolute and relative
  tolerances.
- Key-path property projection matching, with synthesized and explicit root
  placeholders.
- Enum-case matching with composable matchers for one or two associated values.
- Native Swift `Regex` matching, including expressions with typed captures.
- A public `CustomMatcher` protocol and `Match.custom` adapter for reusable
  matcher packages.
- Copy/paste-ready `when` registrations in missing and nonmatching stub
  diagnostics, with escaped literals and a compiling TODO return handler.
- Swift Testing failure artifacts for scoped interaction timelines and lazy
  recording-session diffs against committed fixtures.
- Strict-scope detection of generated values, injected closures, and
  controllers that outlive their Swift Testing test body.
- Strict-scope detection of async invocations that remain unfinished when a
  Swift Testing test body returns.
- Strict-scope detection of invocation streams with matching calls left
  unread, while accepting streams ended through task cancellation.
- Stable, scope-local automatic names for unnamed doubles, including explicit
  case-qualified names in parameterized Swift Testing tests.
- Batch manual-stub generation for every supported protocol in a Swift source
  file or recursively scanned directory.
- A SwiftPM build-tool plugin that automatically regenerates and compiles
  manual-stub conformers when a target's protocol sources change.
- Public `Stub.prewarm()` support for resolving and caching automatic protocol
  preparation plans without constructing a test double.
- Per-stub construction and dispatch performance snapshots with phase timing,
  pending/completed counts, and slowest-method aggregates.
- `ClientStub` now gives concrete closure-field dependency clients the same
  `when`/behavior/verification engine as protocol and manual stubs. One typed
  endpoint router supports nullary and arbitrary-arity synchronous, throwing,
  async, async-throwing, and typed-throws operations without runtime protocol
  metadata or executable trampolines.
- `ClientSpy` forwards unmatched closure endpoints to a live client while
  recording delegated calls, and selective overrides compose with
  `thenForward()`. `ClientDoublePreset` reuses one endpoint mapping for live,
  failing, spying, and partially overridden variants. Synchronous and
  asynchronous configuration closures prepare controllers in one expression,
  while `testValue` directly materializes lightweight test overrides.
- The opt-in `@StubbableClient` macro derives a `ClientDoublePreset` namespace
  from a concrete struct's stored closure fields, including ordinary generic
  clients, nested closure aliases, required configuration values, and
  initialized immutable closure defaults. It now generates private storage
  wiring independently of the client's initializer surface, and explicitly
  marked global, imported, and generic closure aliases retain arbitrary arity,
  async, untyped throws, and typed throws.
- Tuple-input closure doubles can expand to arbitrary-arity functions and use
  separate typed arguments in matchers and computed behaviors across every
  synchronous, throwing, async, and async-throwing variant.
- Standalone closure spies forward unmatched synchronous, throwing, async, and
  async-throwing calls to an existing closure while retaining selective
  overrides, explicit `thenForward()`, and forwarded/stubbed histories.
- Dedicated `SendableClosureDouble` variants constrain inputs and results to
  `Sendable` and expose checked `@Sendable` function values for injection
  across tasks and isolation domains.
- Synchronous and asynchronous typed-throws closure doubles expose precise
  `throws(Failure)` injection signatures, checked `@Sendable` forms,
  forwarding spies, and arbitrary-arity tuple expansion.

### Fixed

- Call-stack capture now compiles as a safe no-op on WASI, whose Foundation
  implementation does not provide `Thread`.

## [0.0.2] - 2026-07-29

### Added

- Injected closures now have effect-aware doubles:
  `ThrowingClosureDouble`, `AsyncClosureDouble`, and
  `AsyncThrowingClosureDouble`. Their dedicated call-pattern types keep input
  inference while exposing the same fluent chains, range verification,
  argument history, streams, `InvocationOrder`, suspension, delays, and
  cancellation controls as the corresponding protocol requirement—without
  offering effects the closure cannot perform.
- Every `Stub`, `Spy`, `ManualStub`, and closure double now exposes a composed
  `history` view with whole-double `callCount`, `wasCalled`, range verification,
  human-readable description, timeline, and `forwarded`/`stubbed` filtering.
  `InvocationOrder.verify` now returns the same session, so saved patterns and
  terminal interaction handles read as one fluent ordered assertion.
- Computed `then`, `thenEscaping`, and `thenForEachCall` handlers now compose
  inside the same fluent behavior chains as `thenReturn` and `thenThrow`.
  `thenForward` can be intermediate too. A bare intermediate behavior is
  one-shot, a bare trailing behavior repeats, and `times:` makes either intent
  explicit, so argument-dependent attempts, fixed fallbacks, and real-target
  recovery can be described in one `when → then → then` expression.
- Timeout-safe asynchronous observation: `InvocationStream.Iterator.next`,
  `StubSuspension.waitForCall`, and `CallbackCapture.waitForCallback` now
  accept `within:` deadlines, with `using:` overloads for deterministic
  `ManualStubClock` tests. Stream timeouts return `nil`; suspension and
  callback timeouts report issues at the waiting call site.
- `when` now returns a reusable `CallPattern` that composes behavior
  registration with call-count verification, typed argument history, and
  future-call streaming. A spy pattern's `forwarded` view provides the same
  count, `wasCalled`, range verification, argument, and stream vocabulary
  scoped to calls that actually reached the forwarding target.
- Automatic discovery now supports an associated-dependent typed error whose
  outer type is a linked, top-level generic class, struct, or enum with one or
  two type parameters. Reconstructed class errors retain Swift's direct
  reference transport, while reconstructed value errors use the formal opaque
  caller-provided error buffer in both synchronous and asynchronous
  requirements. Optional and other unproven value wrappers stay fail-closed.
- Automatic discovery and linked type resolution now reconstruct supported
  generic structs and enums, not only classes, for dependent arguments,
  results, nested generic arguments, and typed errors. Their formal opaque
  witness-value convention is preserved even if a concrete specialization
  would otherwise fit in registers.
- Runtime performance comparisons now resolve one shared package dependency
  graph for the baseline and candidate, so an Echo update cannot appear as a
  TestDoubles performance regression merely because the two measurements used
  different checkouts.
- Bound associated-type resolution now accepts a linked, top-level generic
  class with a protocol-constrained type parameter (`Box<Value: Hashable>`),
  not only unconstrained ones, sharing the same witness-table key-argument
  path the standalone constrained-generic resolution above uses. Covers both
  a dependent argument/result embedding such a class and an
  associated-dependent typed error whose outer type is one.
- Automatic and linked mangled-type discovery now reconstruct metadata for
  generic nominal types whose parameters carry protocol conformance
  requirements, not only unconstrained ones. A public, top-level `struct
  Box<T: Codable>` (or `enum`/`class`) resolves the same way `Array` or
  `Optional` already do, verified against swiftlang/swift's own generic
  key-argument layout: one witness table per constrained parameter, up to
  four key arguments total. A parameter constrained by more than one
  protocol at once, a same-type or base-class requirement, or an argument
  that doesn't actually conform remains fail-closed.
- Tuple arguments and results of any arity now resolve through automatic and
  linked mangled-type discovery, the same as any other supported shape.
  Metadata reconstruction previously wrapped the runtime's fixed 2- and
  3-element tuple entry points and silently failed closed past 3 elements;
  it now calls the general entry point directly.
- SIMD arguments and results (`SIMD2` through `SIMD64`, over any concrete
  `SIMDScalar`) now resolve through automatic and linked mangled-type
  discovery as well, for every already-ABI-supported concrete shape.
  Explicit `.method(signatureOf:)` requirements remain available but are no
  longer required just to name a SIMD type.
- Forwarding `Spy` now supports up to two spilled general-purpose stack
  words on its synchronous outgoing path, drawn from any mix of overflowing
  visible arguments and the target's own metadata/witness-table pair.
  Neither half of that pair is reserved a fixed register: each independently
  lands wherever the target witness's own competitive register allocation
  puts it, matching the real target's compiled calling convention exactly.
  Untyped and typed throws compose freely with the spill. Async forwarding
  also now supports untyped throws alongside its existing one-spill limit;
  a typed throw there still requires its own additional hidden word and
  remains fail-closed.
- Cross-build validation and a real, running demonstration of
  `wasm32-unknown-wasip1` support: CI builds the `TestDoubles` library in
  debug and release with the official Swift 6.3.1 WASI SDK, then both runs a
  small standalone executable and the `TestDoublesWasmTests` suite under
  `wasmtime` (`swift-testing` itself runs there, not just plain code),
  proving `ManualStub` works fully there (no runtime code generation needed)
  while `Stub`/`Spy` construction fails closed with the usual `StubError`
  diagnostic, the same story as physical Apple devices — except WASI can't
  run the trampoline at all rather than merely disallowing it, since it has
  no executable-memory facility. Requires Echo 0.0.6 or newer, whose C
  declarations avoid a wasm32 compiler crash on unprototyped functions.
- `thenRecord(as:into:calling:)` captures a `Spy` registration's result into a
  `RecordingSession`, keyed by a caller-chosen label, in addition to returning
  it as usual — typically wired to call straight through to the real
  dependency being spied on. Freeze a session into an `InteractionFixture`
  with `snapshot()` or persist it as JSON with `save(to:)`. Later,
  `thenReplay(as:from:)` configures fixed responses on a plain `Stub` from a
  fixture's recorded calls under that label, in recording order, exactly like
  a `thenReturn(_:_:_:)` chain built from playback: the last recorded response
  repeats for every call after that. This turns `Spy`'s forwarding boundary
  into a record-once, replay-everywhere fixture for a real dependency, so
  tests stop depending on it being reachable or deterministic. Only successful
  results are recorded; a thrown error still propagates but is not captured.
  Both sides require the requirement's `Result` to round-trip through
  `JSONEncoder`/`JSONDecoder`.
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
  Match.any(), value: Match.any()) }`. Components bind to the requirement's arguments
  from the front, matchers filter which calls are included, and reading is a
  pure query that neither verifies, consumes configured behavior, nor
  commits captors. `returning:` overloads cover results that need a valid
  recording placeholder.
- `clearConfiguredBehaviors()` removes every `when` registration while
  preserving the invocation log, returning a `Spy` to pure forwarding, and
  `reset()` restores the just-constructed state on `Stub`, `Spy`, and
  `ManualStub` by clearing behaviors and invocations together. Manual
  conformers forward a protocol requirement named `reset` through
  `stub.requirements.reset()` to avoid colliding with the controller operation.
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
- `Match.Placeholders` registers suite-wide factories for recording
  placeholder values, so class and existential arguments and results no
  longer need `using:` or `returning:` at every `when`/`verify` site.
  Explicit `using:`/`returning:` values win over registered factories, and
  registered factories win over synthesized values; registered values are
  used only during the recording pass and are never matched against or
  returned.
- Rich argument matchers that compose on the existing matching engine:
  logical combinators `Match.not`, `Match.allOf`, `Match.anyOf`, and
  `Match.oneOf`; the equality and identity matchers `Match.notEqual` and
  `Match.identical(to:)`; the comparison matchers `Match.greaterThan`,
  `Match.atLeast`, `Match.lessThan`, `Match.atMost`, and `Match.inRange`; the
  optional matchers `Match.isNil`, `Match.notNil`, and `Match.some`; the
  collection matchers `Match.isEmpty`, `Match.nonEmpty`, `Match.hasCount` (by
  value or nested matcher), `Match.contains`, `Match.contains(where:)`,
  `Match.containsAll`, `Match.startsWith`, and `Match.endsWith`; and the
  string matchers `Match.hasPrefix`, `Match.hasSuffix`,
  `Match.containsSubstring`, `Match.equalsIgnoringCase`, and
  `Match.matchesRegex`. Combinators fold nested matchers into a single
  positional matcher, so
  `Match.allOf(captor.capture(), Match.greaterThan(0))` captures only the
  arguments that satisfy the whole expression, and composed matchers keep
  legible diagnostic descriptions.
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

- Fixed behavior repetition now has two intentional forms: `times: 2` serves
  an exact finite run that can continue into another `then` step, while
  `times: 1...` is an unbounded terminal. The redundant bounded-range
  spellings such as `times: 1...2` have been removed. When `times:` is
  omitted, a bare intermediate behavior is exactly once and a bare trailing
  behavior is implicitly unbounded. Unbounded
  `thenReturn`, `thenThrow`, and `thenDoNothing` terminals, variadic
  `thenReturn`, and `thenFatalError` now return an observation-only
  `CallInteractions` handle, so a completed fluent chain can be saved and
  later verified, queried for arguments, streamed, or narrowed to forwarded
  spy calls without allowing another behavior after its terminal answer.
- Every ordinary terminal configuration now returns the same
  `CallInteractions` view, including custom and counted handlers, forwarding,
  cancellation, record/replay, initializer, and dynamic-`Self` behaviors.
  `StubSuspension` and `StubBehaviorQueue` compose that view through
  `.interactions`, keeping observation available alongside resume and
  exhaustion controls. Explicit `thenForward()` calls are now correctly
  classified as forwarded interactions as well.
- A plain immediate `verify()` now expects exactly one matching call, matching
  the conventional Mockito-style meaning and catching accidental duplicates.
  Native ranges remain the primary spelling for every other count expectation,
  while eventual verification continues to default to the monotonic `1...`.
- `InvocationOrder.verify` now accepts saved `CallPattern` and
  `CallInteractions` values directly, so cross-double ordering composes with
  `when`/`then` setup without repeating either call-capture closure.
- Dispatch-specific observation is now symmetric and composed:
  `interactions.forwarded` and `interactions.stubbed` are filtered
  `CallInteractions` values with the complete count, range, argument, stream,
  eventual-verification, and ordering API. The duplicate nested forwarding
  wrapper types have been removed.
- `ClosureDouble` and `VoidClosureDouble` now use the shared recorder and
  `when → then → verify` behavior model. The new typed `ClosureCallPattern`
  preserves closure-input inference while adding contextual fixed chains,
  `thenForEachCall`, queues, `CallInteractions`, streams, range verification,
  strict-scope diagnostics, ordering, lifecycle controls, and interaction
  logs. Terminal closure behaviors now return observable handles instead of
  `Void`.
- The pre-release `StubBuilder` type and the separate
  `forwardedCallCount`/`forwardedArguments()` pattern members have been
  replaced by `CallPattern` and its composed `forwarded` view.
- Verification now uses native `RangeExpression<Int>` values as its primary
  vocabulary: `2...`, `...2`, and `2...4` express lower bounds, upper bounds,
  and closed ranges directly. `.exactly(2)` and `.never` remain conveniences
  for the two cases that ranges spell less clearly. Eventual verification
  accepts a monotonic lower-bounded range such as `2...`.
- Argument matching is now one discoverable API family under `Match`.
  Top-level matcher functions moved to static methods such as `Match.any()`,
  `Match.equal(_:)`, and `Match.allOf(_:_:)`; `ArgumentCaptor` became
  `Match.Capture`; and `RecordingPlaceholders` became `Match.Placeholders`.
  The pre-release top-level spellings no longer exist.
- CI now snapshots every exported product API, rejects undocumented public
  symbols, compiles generated manual stubs against their protocols, and
  enforces coverage for the generator, Swift Testing integration, and C
  trampoline sources.
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

- Runtime performance CI now builds each revision's native benchmark driver
  while keeping both revisions on the candidate dependency graph. Intentional
  public API breaks therefore remain benchmarkable without compiling new
  workload source against the old API.
- `ClosureDouble`, `VoidClosureDouble`, and `CallbackCapture` no longer claim
  unconditional `Sendable` safety, and user matchers and handlers execute
  outside internal locks so reentrant calls cannot deadlock.
- Cancelling `StubSuspension.waitForCall(count:)` now removes and resumes its
  waiter without leaking a continuation, including cancellation races.
- Manual-stub generation preserves static argument types in route identities,
  emits typed-throws metadata, routes property and subscript setters, and
  produces a compiling trailing-newline-stable file.
- `InteractionFixture` decoding now rejects invalid and unsupported future
  schema versions instead of interpreting them as the current format.
- Native macOS test bundles no longer link a current-runtime custom-executor
  hook when built for the package's older deployment target.
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

[Unreleased]: https://github.com/tevelee/swift-test-doubles/compare/0.0.2...HEAD
[0.0.2]: https://github.com/tevelee/swift-test-doubles/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/tevelee/swift-test-doubles/tree/0.0.1

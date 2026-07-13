# Stub Contract

Understand how ``Stub`` is constructed, configured, and verified, and where its
runtime support boundary lies.

## Overview

For task-oriented examples built on this contract, see <doc:GettingStarted>.

### Construction

``Stub`` has one throwing initializer with two modes. With no requirements, it
discovers signatures from a concrete conformance linked into the process. With
typed ``Stub/Requirement`` values, it fabricates a conformance without needing
a real implementation.

Explicit requirements are positional. Their kinds, types, and method effects
must exactly match the protocol declaration. Construction validates all
reliably discoverable components before allocating runtime state. Getter
throwing behavior remains caller-supplied because witness symbols do not encode
it. Detectable failures are reported as ``StubError`` values.

### Configuration and selection

`when` records one protocol invocation using matcher arguments. Finish a
value-returning configuration with `returns` for a constant or `then` for typed
behavior. A bare `when` installs the no-op fallback for a `Void` requirement.
Handlers accept arbitrary arity through Swift parameter packs. Async handlers
may suspend as part of the caller's task, preserving task-local values,
cancellation, and priority. Handler actor isolation is respected, including on
a custom serial executor, and an isolated caller resumes on its executor.

When multiple registrations match, explicit equality outranks a literal, a
literal outranks a predicate, and a predicate outranks `any()` or capture. The
first registration wins a tie. Literal matching is best-effort textual
matching; prefer `equal(_:)` for meaningful equality.

### Verification

`verify` checks a recorded invocation immediately and defaults to at least one
matching call. Use ``Stub/CallCount/exactly(_:)`` or ``Stub/CallCount/never``
when the count expresses meaningful behavior. An ``ArgumentCaptor`` in the
verification call captures matching arguments for later assertions.

### Supported protocol shapes

Stub supports instance methods and ordinary getters on a single,
non-class-constrained protocol without inherited or associated requirements.
Methods may be synchronous, throwing, async, or async-throwing. Effectful
getters require explicit requirements.

Supported value shapes include integer and floating-point values, direct and
indirect aggregates, `Void`, existentials, optionals, enums, tuples, metatypes,
and strings. These source-level types share runtime calling-convention
machinery; they do not each need a dedicated stubbing API.

### Unsupported protocol shapes

- Function and closure arguments or returns, which require compiler-generated
  closure reabstraction.
- Protocol compositions.
- Read-write properties and class-constrained, inherited, associated-type,
  initializer, static, `_read`, and `_modify` requirements.
- Async getters discovered automatically, because their effects cannot be
  determined safely. Describe effectful getters explicitly.
- Existential-typed matcher placeholders created by `any()`. Use a concrete
  conforming value while recording that invocation.
- Concrete or final methods and devirtualized calls, because only protocol
  witness calls can be intercepted.

When no linked conformance is available, protocol metadata exposes requirement
count and kind but not complete signature types or effects. A mismatched
caller-supplied signature therefore violates the ABI contract even if it cannot
be diagnosed during construction.

### Runtime and platform boundary

CI-backed release support covers macOS 13+, the arm64 iOS 16+ Simulator, and
Ubuntu 24.04. The runtime executes on arm64 and x86_64 where those architectures
are available; macOS x86_64 coverage runs under Rosetta. Apple deployment
targets are compiled at their declared minimum and executed on CI's available
runner or simulator OS. Physical iOS devices are unsupported because the
runtime generates executable trampoline code and CI cannot exercise device
execution policy.

On x86_64, construction rejects async requirements whose arguments and indirect
result consume all six general-purpose argument registers. That continuation
boundary is supported on arm64.

### Ownership and concurrency

Configure a stub serially before invoking it concurrently. Recorder state is
lock-protected, but a handler is responsible for synchronizing any mutable state
it captures. Keep the owning ``Stub`` alive while using its fabricated protocol
value.

See <doc:TrampolineArchitecture> for the implementation behind this contract.

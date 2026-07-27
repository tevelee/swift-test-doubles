# Projection-Only Recorder for Noncopyable/Lifetime-Dependent Values — Design Notes

Status: **architectural, not implemented.** This is a real redesign of how invocations
get recorded, not an additive feature — every existing recording path assumes a value
can be boxed into `Any` and copied freely. Below is the current architecture's actual
boxing surface, why that's fundamentally incompatible with `~Copyable`/lifetime-dependent
values, and a sketched alternative that doesn't require rewriting everything at once.

## Where the `Any`-boxing assumption actually lives

This is deeper than one file. Tracing an argument from the trampoline to a match
assertion:

- `Sources/TestDoubles/Recording/InvocationLedger.swift` stores every recorded call's
  arguments as `[Any]` (`args: [Any] { argumentsStorage.values }`, line 136) and even
  offers a `.weak(...)` storage variant (line 60-117) that boxes an
  `Optional(weak.value ?? materializer.requirePayload()) as Any` — the weak-reference
  path *still* produces an `Any` at the point of retrieval.
- `Sources/TestDoubles/Recording/ParameterMatcher.swift` and `Matchers.swift` compare
  and describe recorded arguments entirely in terms of `Any`-typed values (equality via
  `_openExistential`-style dynamic dispatch, description via `String(describing:)`).
- `Sources/TestDoublesRuntime/Runtime/PlaceholderValue.swift`/
  `Sources/TestDoubles/Recording/RecordingPlaceholders.swift` (the "argument capture"
  mechanism for `.willReturn`/verification builders) work by substituting a placeholder
  `Any` value and later resolving it — again, a value that must exist as a freestanding,
  copyable box independent of the original call's stack frame.
- Further upstream, `Sources/TestDoublesRuntime/Runtime/FunctionBridgePlan.swift`
  already refuses noncopyable values at the boundary before any of the above is even
  reached: a noncopyable result, typed error, or parameter each get their own explicit
  rejection, and `Sources/TestDoublesRuntimeMetadata/Metadata/ProtocolLayout+Builder.swift:602-622`
  (`invertedProtocolDiagnostic`) rejects whole protocols that relax `~Copyable`/
  `~Escapable` with a message that says exactly why: *"Runtime test doubles record
  escaping `Any` values, which require copyable, escapable payloads."*

## A deeper barrier than the boxing assumption: `~Escapable` isn't representable as `Any.Type` here at all

Tried to verify the `isAddressableForDependencies` value-witness flag (below) against a
real `~Escapable` type, `Swift.Span`, the way this codebase already reflects every other
type — `ValueLayoutInfo(reflecting: Span<UInt8>.self)`. It doesn't compile:

```
error: argument type 'Span<UInt8>' does not conform to expected type 'Escapable'
```

`FunctionBridgeAnalysis`'s `resultType`/`parameterTypes` (and essentially every other
type-erased slot throughout this codebase) are typed as plain `Any.Type`. Converting a
`~Escapable` type's metatype to the `Any` existential's metatype requires the underlying
type to conform to `Escapable`, because `Any` itself carries an implicit
`Escapable & Copyable` requirement. A genuinely `~Escapable` type's metatype cannot be
stored in an ordinary `Any.Type`-typed variable at all with today's generics model
(short of the newer, much less commonly supported `any ~Escapable` existential form,
which nothing in this codebase's type-erasure layer uses). Practically: this means the
current architecture would fail to even *carry* a `~Escapable` parameter's type as far
as `FunctionBridgePlan`'s existing noncopyable check — something upstream of it
(signature discovery, generic metadata resolution) would need its own `~Escapable`-aware
type-erasure representation before this check is ever reached. That's a second,
independent architectural barrier on top of the `Any`-boxing one above, not solved by
anything below.

That's the honest current architecture: copyability is checked at the boundary
specifically *because* everything downstream assumes it. There's no partial noncopyable
support to extend — the checks exist to protect a design that's `Any`-shaped from the
ground up.

## What the runtime already exposes, if this were tackled

Value-witness introspection is richer than the current noncopyable gate uses. Echo's
`ValueWitnessTable.Flags` (`.build/checkouts/Echo/Sources/Echo/Metadata/
MetadataValues.swift:344-410`, surfaced through `EchoRuntimeReflection.ValueLayoutInfo`)
separately exposes:

- `isCopyable` (`bits & isNonCopyable == 0`) — the actual `~Copyable` check, and the only
  one `FunctionBridgePlan`/`RuntimeValueLayout.swift:112,460` currently reads.
- `isBitwiseBorrowable` (`isBitwiseTakable && bits & isNonBitwiseBorrowable == 0`) — a
  distinct axis from copyability: whether a *borrowed* value of this type can be passed
  by bitwise value. Unused anywhere in this codebase today.
- **`isAddressableForDependencies`** (`bits & isAddressableForDependencies != 0`) —
  "whether values of this type must be passed indirectly when producing
  lifetime-dependent values that could reference their inline storage." This is exactly
  the lifetime-dependency signal this item is aiming at, and it's already a plain
  boolean read, no new runtime work needed to detect it. Also unused anywhere in this
  codebase today.

There's still no existing general address-only-layout classification (a grep for
`addressOnly` in `Sources/` turns up nothing) — `isCopyable`/`isAddressableForDependencies`
are boolean gates, not a full layout classification. A projection-only recorder would
still need to reason about "can I safely take a *reference* to this value's storage for
the duration of one recorded call without violating Swift's exclusivity rules," which
these two flags inform but don't fully answer.

## What was actually implemented (the classification half, not the recorder)

`FunctionBridgePlan.swift`'s three noncopyable rejection sites (result, typed error, each
parameter) now route through one `noncopyableDiagnosis(for:role:)` helper that checks
`isAddressableForDependencies` after `isCopyable` fails, and produces a message that
names the lifetime-dependent case specifically instead of a generic "is noncopyable."
This is deliberately narrow: it improves the diagnostic for whatever noncopyable types
*can* reach this check today (ordinary `~Copyable`, still-`Escapable` types), but per the
barrier described above, a genuinely `~Escapable` type like `Span` can't be represented as
this codebase's `Any.Type` in the first place — so this change cannot, by itself, make
`Span` produce a better message; it's only reachable if a future `~Escapable`-aware
type-erasure layer gets built and needs a copyability/lifetime diagnostic to plug into.
Landed anyway because it's a real, if narrow, improvement today and it's the one piece of
groundwork from this whole design that was concretely safe to do without committing to
the rest.

## Sketch: a projection-only recorder

The core idea: instead of *storing a copy* of an argument, record a **projection** — a
small, fixed-shape, always-copyable description plus (when safe) a borrowed pointer
whose validity is scoped to the call, rather than an owned box that outlives it.

1. **Never construct `Any` for a noncopyable/address-only value.** The dispatch path
   already knows the value's static type and ABI class before it ever needs to box
   anything (`RuntimeArgumentDecoder`, `MethodDescriptor`) — a noncopyable argument would
   route through a different recording call that takes an `UnsafeRawPointer` to the
   argument's storage plus its `Any.Type`, never an `Any`.
2. **Record a projection, not the value.** A projection is what today's
   `InvocationLedger`/matchers actually need to answer "did this call happen, with
   arguments matching this pattern": a type identity, a stable structural fingerprint
   (e.g. a hash of the value's bytes for a trivially-copyable-but-move-only type, or a
   caller-supplied projection closure for anything with reference semantics inside), and
   optionally a human-readable description string computed *eagerly* (`String(describing:)`
   equivalent) at record time, since the description is always copyable even when the
   value isn't. This means matchers would compare projections, not values — a real
   change to `ParameterMatcher`'s contract, not just its implementation.
3. **Lifetime-dependent values need the projection captured strictly during the call.**
   A `~Escapable`/lifetime-dependent value (the `Span`-shaped case this item is really
   aiming at) cannot be retained past the call that produced it under any circumstance —
   so unlike ordinary recording (which keeps arguments alive in the ledger for later
   assertion), a lifetime-dependent argument's projection must be fully computed
   (fingerprint + description) synchronously inside the dispatch call, with nothing
   pointer-shaped surviving it. This is a strictly narrower contract than what
   `InvocationLedger` offers today for everything else, and it means verification
   builders that currently defer work against a stored `Any` (`PlaceholderValue`,
   `.willReturn` argument capture) fundamentally can't offer the same deferred-access API
   for these arguments — only immediate, in-call assertions would be possible.
4. **`~Copyable` (escapable, movable) values are the more tractable half.** These can be
   *moved into* ledger storage instead of copied, if the ledger's storage model added a
   move-only-friendly variant alongside `.strong(Any)`/`.weak(...)`
   (`InvocationLedger.swift:60-117`) — e.g. a `.projection(TypeErasedProjection)` case
   that never requires `Any` conformance. This is real, incremental work, but at least
   it doesn't fight Swift's escapability rules the way the lifetime-dependent case does.

## Why this is architectural, not additive

Every consumer of a recorded argument today — matchers, descriptions, placeholder
resolution, `.willReturn` capture — is written against "I have an `Any`, I can copy it,
compare it, describe it, hold onto it indefinitely." A projection-only path means a
second, parallel contract for noncopyable/lifetime-dependent arguments that doesn't
support some of those operations at all (holding onto it indefinitely, in particular).
That's not a new case in a switch statement; it's a second recording model living
alongside the first, with matchers and builders that need to know which one they're
looking at.

## Recommendation

Don't implement the recorder now — it's a real architecture change gated on a concrete
driving use case, and (per above) genuinely `~Escapable` values can't even reach it with
today's `Any.Type`-based type erasure. The one safe, small step (better-classified
diagnostics at the existing rejection boundary, landed alongside this doc) is done; the
rest should wait.


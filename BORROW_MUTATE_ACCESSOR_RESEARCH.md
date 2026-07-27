# First-Class `borrow`/`mutate` Accessors — Feasibility Spike

Status: **confirmed blocked on toolchain, with one correction to how this was
originally framed.** Read directly from `swiftlang/swift`'s AST/SIL/IRGen source
(fetched fresh from GitHub `main`, not just the local sparse checkout, specifically to
avoid the kind of stale-checkout mismatch this validation effort has already hit once
this week). No code changes attempted — there is nothing to verify a change against.

## Correction to the initial framing

The premise going in was "Swift main now emits direct protocol dispatch thunks for
these, with a new borrow metadata/runtime representation" — implying a new
`ProtocolRequirementFlags::Kind` enumerator alongside `ReadCoroutine`/`ModifyCoroutine`.
That's not what's there. Fetched `include/swift/ABI/MetadataValues.h` fresh from
`swiftlang/swift@main` right now and confirmed `ProtocolRequirementFlags::Kind` still
has exactly the same nine values this repo already knows about (`BaseProtocol`,
`Method`, `Init`, `Getter`, `Setter`, `ReadCoroutine`, `ModifyCoroutine`,
`AssociatedTypeAccessFunction`, `AssociatedConformanceAccessFunction`) — no `Borrow`, no
`Mutate`.

What's actually there, from `lib/IRGen/GenMeta.cpp` (the exact function that classifies
an accessor into a `ProtocolRequirementFlags::Kind` for witness-table purposes):

```cpp
case AccessorKind::Read:            return {Flags::Kind::ReadCoroutine, false};
case AccessorKind::YieldingBorrow:  return {Flags::Kind::ReadCoroutine, true};
case AccessorKind::Modify:          return {Flags::Kind::ModifyCoroutine, false};
case AccessorKind::YieldingMutate:  return {Flags::Kind::ModifyCoroutine, true};
case AccessorKind::Borrow:
case AccessorKind::Mutate:
  return {Flags::Kind::Method, false};
```

So the correction is: `borrow`/`mutate` witnesses are **not** a new witness-table kind
at all — they're classified as ordinary `Kind::Method`, the same slot an ordinary
function requirement uses. "Direct protocol dispatch thunk" was the right instinct (no
coroutine, no yield, no ramp function) — it's just that the ABI achieves that by reusing
the plainest existing witness kind, not by adding a new one. This is actually good news
for future implementation cost: whatever dispatch machinery this repo already has for
`.method`-kind requirements is architecturally the right starting point, not a new
witness-table shape to reverse-engineer from scratch.

## What's genuinely new, and why it's not shippable yet

The calling convention riding on top of that reused `Method` kind is real and not yet
representable by this codebase. From `lib/SIL/IR/SILFunctionType.cpp`
(`ResultConventionClassifier`, function starting ~line 1541):

- `isBorrowAccessor(constant)` gates a distinct result-convention path: a `borrow`
  accessor's result is classified `ResultConvention::Guaranteed` or, for
  address-only/addressable-for-dependencies results, `ResultConvention::GuaranteedAddress`
  — a genuinely new convention this repo's `ABIClass`/result-encoding model
  (`RuntimeResultEncoder.swift`, `RuntimeResultTransportPlan.swift`) has no case for
  today. Every existing result path in this repo assumes an owned return (ordinary
  getter) or a coroutine yield (`read`/`modify`); "guaranteed, possibly address-based, via
  an ordinary direct call" is a third shape.
- Tuple results are **deliberately not destructured** for borrow/mutate accessors
  (`"Do not explode tuples for borrow and mutate accessors since we cannot explode and
  reconstruct addresses"`) — the opposite of ordinary method-result handling, which does
  explode tuples.
- Returning a parameter pack from a borrow/mutate accessor is **explicitly
  unimplemented in the compiler itself**: `llvm_unreachable("Returning packs from
  borrow/mutate accessor is not implemented")`. This is not a stable, finished ABI
  surface — it's still being built out upstream.

## Confirmed: cannot be tested against a live compiler today

The local pinned toolchain is Swift 6.3.3 (`swift-6.3.3-RELEASE`). A minimal probe:

```swift
protocol P { var value: Int { borrow; mutate } }
```

fails to parse at all: `"expected get or set in a protocol property"` /
`"property in protocol must have explicit { get } or { get set } specifier"`. The
`borrow`/`mutate` accessor keywords aren't recognized as accessor syntax by this
toolchain. Every other fix landed this week in this codebase (the `yield_once_2`
discriminator fix, the `.read2` accessor-marker correction) was only trustworthy because
it could be checked against real compiler output — the lesson from that work applies
directly here: reading upstream source without a live compiler to cross-check against is
exactly how a wrong "fix" gets shipped with false confidence. There is no live compiler
available for this feature, so no code change is attempted.

## What TestDoubles would need, once a toolchain supports this

For a future session, once a Swift toolchain that parses `borrow`/`mutate` accessors is
available:

1. Recognize the `.borrow`/`.mutate` demangled accessor spellings in
   `WitnessSignatureParser` (this repo already treats `.borrow` as a spelling variant
   fed into the *existing* `.readCoroutine` path per the recent accessor-marker fix —
   that mapping would need to be reconsidered once `borrow` denotes a genuinely
   non-coroutine `Method`-kind witness instead).
2. Add a `GuaranteedAddress`/`Guaranteed`-result case to the ABI classification this repo
   uses for ordinary method results, since it's currently binary (owned direct value vs.
   coroutine yield).
3. Handle the "don't explode tuple results" special case for these two accessor kinds
   specifically, diverging from ordinary method-result tuple handling.
4. Treat pack-returning borrow/mutate accessors as fail-closed indefinitely — the
   compiler itself doesn't support them, so there's no ABI to target even in principle
   yet.

## Recommendation

No code change. This genuinely is a "wait for the toolchain" item, and the research
above is the useful artifact: it corrects the "new witness kind" assumption (it's
`Method`, not a new `Kind`), narrows exactly what new machinery would be needed (a third
result-convention shape, not a new dispatch mechanism), and confirms there is no way to
verify an implementation today. Revisit when a Swift toolchain that accepts `borrow`/
`mutate` accessor syntax ships.

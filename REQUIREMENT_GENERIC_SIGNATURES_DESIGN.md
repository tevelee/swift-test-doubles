# Requirement-Level Generic Signatures (incl. Parameter Packs) — Design Notes

Status: **fails closed with a specific diagnostic; full support gated on an API design
question, not on runtime effort.**

Two corrections landed here after attempting implementation, and both change the shape of
the item:

1. The runtime cost was **overestimated**. This doc originally called the pack calling
   convention the blocker, based on reading upstream IRGen; measuring the actual lowered
   witness disproved that (see "The witness ABI, measured"). The trampoline needs no
   changes at all.
2. The scope was **underestimated**. Parameter packs are not an isolated gap — they sit on
   top of *requirement-level generic signatures* in general, which are equally
   unsupported (see "Packs are blocked on a larger missing feature"). `func g<T>(_ v: T)`
   fails for the same underlying reason, and is the more sensible first milestone.

## What already exists (don't re-solve this part)

Requirement *handler* arity is already fully pack-based throughout the `Doubles` layer —
`Stub`/`Spy` handler closures accept `repeat each Argument`
(`Sources/TestDoubles/Doubles/StubInvocation.swift`,
`Sources/TestDoubles/Doubles/StubBuilder.swift`,
`Sources/TestDoubles/Doubles/TypedHandlerInvocation.swift`). That's the Swift-API-facing
use of packs (how many arguments a *stubbed* method takes) and has nothing to do with
this item. The one known gap there is narrow and already documented in-place
(`StubBuilder.swift:349-352`): an escaping closure nested inside a pack argument loses
its escaping convention, requiring a separate non-pack overload for the first argument.
Leave that alone; it's unrelated to what follows.

This item is about something else: a **protocol requirement whose own generic signature
uses a parameter pack**, e.g.:

```swift
protocol P {
    func f<each T>(_ args: repeat each T)
}
```

## Confirmed: this is real, live, and currently fails closed correctly

Verified against the local Swift 6.3.3 toolchain (this is not a future-toolchain
question the way item 10 is — packs as protocol requirements compile and produce a real
witness today):

```
$ swiftc -emit-sil packreq.swift   # compiles cleanly
$ nm libpackreq.dylib | swift-demangle
protocol witness for packreq.P.f<A>(repeat A1) -> () in conformance packreq.S : packreq.P in packreq
protocol witness table for packreq.S : packreq.P in packreq
```

And in this repo, discovery fails closed (not silently, not incorrectly) when a protocol
has a requirement shaped like this. It originally reported only the raw demangled
spelling:

```
Could not discover the signature of 'PackRequirementProbe' requirement 0.
Could not resolve runtime metadata for type 'repeat A1'. Supply explicit Requirement values.
```

which named neither the feature nor why it was unsupported. It now says so directly, and
this stays the fallback for any shape the feature doesn't cover:

```
Requirement 0 has a parameter-pack argument ('repeat A1'). Automatic Stub does not
support requirements whose own generic signature uses a parameter pack. Supply
explicit Requirement values.
```

## The witness ABI, measured (this corrects an earlier assumption in this doc)

An earlier revision of this section, written from reading `lib/IRGen/GenPack.{h,cpp}`
upstream, claimed the central blocker was **dynamic register arity** — that a pack
requirement "needs the *trampoline itself* to iterate a runtime-determined number of
stack/register slots." **That is wrong**, and it materially overstated the cost. Compiling
an actual pack requirement and reading its lowered witness shows the opposite.

For `protocol P { func f<each T>(_ args: repeat each T) -> Int }`, the witness lowers to
(`swiftc -emit-sil` / `-emit-ir`, Swift 6.3.3, arm64):

```
sil @...TW : $@convention(witness_method: P) <each τ_0_0>
  (@pack_guaranteed Pack{repeat each τ_0_0}, @in_guaranteed S) -> Int

define swiftcc i64 @"...TW"(
    ptr noalias %0,                     ; pack buffer
    i64 %1,                             ; pack length (shape)
    ptr %"each τ_0_0",                  ; metadata pack
    ptr noalias nocapture swiftself %2, ; self, indirect
    ptr %Self, ptr %SelfWitnessTable) 
```

The physical arity is **fixed at six**, all in registers the trampoline already captures
today. The dynamism lives entirely *behind* the pack pointer. The witness body shows
exactly how to walk it:

```llvm
%9  = and i64 %8, -2                            ; mask the metadata pack's low tag bit
%11 = getelementptr inbounds ptr, ptr %10, i64 %5 ; metadataPack[i]
%12 = load ptr, ptr %11                          ; -> element i's type metadata
%13 = getelementptr inbounds ptr, ptr %0, i64 %5  ; packBuffer[i]
%14 = load ptr, ptr %13                          ; -> element i's ADDRESS
```

So decoding a pack argument into `[Any]` is a plain loop over two parallel pointer
arrays, given the count that arrives in an ordinary register:

- **pack buffer**: array of pointers, element *i*'s address at `buffer[i]`
- **metadata pack**: pointer tagged in bit 0 (mask `& ~1`, matching `maskMetadataPackPointer`
  in `GenPack.h`), then `metadataArray[i]` is element *i*'s `Any.Type`
- **count**: a direct `i64` register argument

Everything needed to box each element already exists in this codebase (`boxValue(type:source:)`
takes exactly a type plus a source address). **The trampoline needs no changes at all.**

What remains genuinely true from the original analysis: `GenericPackShapeHeader`/
`GenericPackShapeDescriptor` (`include/swift/ABI/GenericContext.h:264-303`) do interleave
packs with ordinary generic arguments behind a separate shape-descriptor table, and
metadata/witness-table packs are allocated and cleaned up dynamically
(`cleanupTypeMetadataPack`, `deallocatePack`, et al). Those matter for the harder
directions — fabricating a witness that must *produce* a pack, or resolving a pack-shaped
generic nominal type — but not for the common case of *receiving* a pack argument.

## Packs are blocked on a larger missing feature: generic requirements

Measured while attempting implementation, and this reframes the item. A plain
**non-pack** generic requirement is equally unsupported:

```swift
protocol P { func g<T>(_ value: T) -> Int }   // no packs anywhere
```

fails discovery identically — previously with the same unhelpful *"Could not resolve
runtime metadata for type 'A1'"*. (`A1` is the demangled spelling of the requirement's own
first generic parameter; `A` alone is `Self`.)

Its witness lowers to the same family as the pack case:

```
; func g<T>(_ value: T) -> Int
swiftcc i64 @witness(ptr %value,        ; the value, INDIRECT
                     ptr %"τ_0_0",      ; T's metadata, in a register
                     ptr swiftself %self, ptr %Self, ptr %SelfWitnessTable)
```

Both shapes are instances of one unimplemented capability: **arguments whose type is
supplied by the caller at runtime via metadata registers**, rather than fixed by the
protocol. A pack is just the variable-length version (`count` + a metadata *pack*)
of what `g<T>` does with one metadata register.

This matters for planning: `MethodDescriptor.arguments` is `[WitnessArgumentDescriptor]`
with concrete `Any.Type`s baked in at discovery time, and the transport plan, decoder,
matcher, and `Stub.Requirement` factories all build on that. Runtime-typed arguments are
a new axis through all of them. So "implement parameter packs" is really "implement
generic requirements, then extend them to variable length" — a substantially larger and
differently-shaped project than this doc originally described, and one whose first
milestone isn't pack-specific at all.

## Revised incremental path

The earlier "step 2" here proposed supporting *fixed small pack arities* "the conforming
type instantiates at a small, fixed length." That idea was incoherent as well as
unnecessary: the pack length is chosen by each **call site**, not by the conforming type,
so there is no per-conformance fixed length to discover. And since arity is not a
trampoline problem at all (see above), there is nothing to sidestep — a loop over the
pack buffer handles any length uniformly.

The real remaining work is not in the ABI layer:

1. **Signature discovery ✅ (shipped).** Both shapes now fail closed with a specific
   diagnostic naming what they are — a parameter-pack argument, or an argument typed by
   the requirement's own generic parameter — rather than a generic "could not resolve
   runtime metadata for type 'A1'."
2. **Argument decoding — small, and now fully specified.** Walk `count`, `packBuffer[i]`,
   `maskedMetadataPack[i]`, box each element with the existing `boxValue(type:source:)`.
   No new ABI reverse-engineering required; the loop above is the whole algorithm.
3. **The actual hard part is the user-facing API, not the runtime.** Everything downstream
   of decoding assumes a requirement has a statically-known argument list:
   - `when { $0.f(...) }` recording works by *calling* the requirement with placeholder
     values and observing which slots were touched. What does a user write to record a
     call to a pack requirement, and how does the builder know the intended arity?
   - Matchers (`ParameterMatcher`) compare positionally against a fixed expected list; a
     pack invocation may have a different length per call.
   - `Stub.Requirement` factories (`.method(...)`, `signatureOf:`) describe a fixed
     parameter list; there is no spelling today for "a pack here."
   - Verification counts (`.exactly(1) { $0.f(...) }`) must decide whether calls with
     different pack lengths are the same requirement invoked differently, or distinct.

   These are API-design questions with real product consequences, not ABI questions.
4. **Producing a pack (a requirement whose *result* or associated type is pack-shaped)**
   remains genuinely hard, and is where the `GenericPackShapeDescriptor` walking and
   pack allocation/cleanup discipline noted above actually bite. Distinct, later problem.

## Recommendation

Step 1 is shipped for both shapes. Beyond it, two things gate progress, and neither is
the ABI reverse-engineering this item was originally scoped around:

1. **Packs are the wrong starting point.** The first milestone should be *generic
   requirements* (`func g<T>(_ value: T)`), which are simpler, strictly more common in
   real protocols, and are the foundation packs extend. Shipping packs without them
   would mean building the variable-length case before the fixed-length one.
2. **The blocker is API design, not runtime work.** Decoding is understood and small, but
   decoded runtime-typed arguments have nowhere to go until the stubbing API decides how
   such requirements are expressed — how a user records an expectation whose argument
   type (or count) is chosen per call site, how matchers compare them, and what
   `Stub.Requirement` spells. Implementing decoding alone would add an unreachable code
   path.

Concretely: revise the *runtime* effort estimate sharply down from "very high," but treat
the item as gated on an API design decision, ideally driven by a real use case, and
re-aim its first milestone at generic requirements rather than packs.

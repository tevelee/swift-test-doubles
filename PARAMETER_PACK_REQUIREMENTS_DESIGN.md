# Parameter-Pack Protocol Requirements — Design & Scoping Notes

Status: **fails closed with a specific diagnostic; full support gated on an API design
question, not on runtime effort.** An earlier revision of this doc estimated the runtime
side as very-high-effort based on a mistaken reading of the pack calling convention;
measuring the actual lowered witness disproved that (see "The witness ABI, measured").
The runtime work is now small and fully specified. What's genuinely unresolved is how
pack requirements should be *expressed* in the stubbing API.

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

And in this repo, discovery already fails closed (not silently, not incorrectly) when a
protocol has a requirement shaped like this:

```
Got expected error: Could not discover the signature of 'PackRequirementProbe'
requirement 0. Could not resolve runtime metadata for type 'repeat A1'.
Supply explicit Requirement values.
```

That's the right behavior today (this codebase's design goal throughout is "fail closed
with a clear diagnostic," not "silently misbehave"), and it should **stay** the fallback
for any pack shape this feature doesn't yet cover. The error message itself could be more
specific (mention parameter packs by name instead of quoting `'repeat A1'` verbatim), but
that's a copy tweak, not the substance of this item.

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

## Revised incremental path

The earlier "step 2" here proposed supporting *fixed small pack arities* "the conforming
type instantiates at a small, fixed length." That idea was incoherent as well as
unnecessary: the pack length is chosen by each **call site**, not by the conforming type,
so there is no per-conformance fixed length to discover. And since arity is not a
trampoline problem at all (see above), there is nothing to sidestep — a loop over the
pack buffer handles any length uniformly.

The real remaining work is not in the ABI layer:

1. **Signature discovery ✅ (shipped).** A pack parameter now fails closed with a specific
   diagnostic naming it, rather than a generic "could not resolve runtime metadata."
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

Step 1 is shipped. Step 2 is now a well-understood, contained piece of work — but it is
**not independently useful**: decoded pack arguments have nowhere to go until step 3
decides how packs are expressed in the stubbing API. Implementing decoding alone would
add an untested, unreachable code path.

So the gating question for this item is a **design** question — "what does stubbing a
pack requirement look like to a user?" — not an engineering-effort question. That should
be answered (ideally against a real use case) before more code is written. The effort
estimate for the runtime side, at least, should be revised sharply downward from the
original "very high."

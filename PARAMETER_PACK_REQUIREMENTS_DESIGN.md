# Parameter-Pack Protocol Requirements — Design & Scoping Notes

Status: **not implemented, very-high-effort**. This is a from-scratch feature, not an
extension of existing pack support. Below is what's already there, what's actually
missing, why it's a large project, and a proposed incremental path — written so a future
session can pick this up without re-deriving the scope.

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

## Why this is a large project (grounded in the actual upstream ABI)

Fetched and read `lib/IRGen/GenPack.{h,cpp}` from `swiftlang/swift` (1,459 lines in the
`.cpp` alone) — this is real, substantial infrastructure, not a small ABI corner:

- **`GenericPackShapeHeader`/`GenericPackShapeDescriptor`**
  (`include/swift/ABI/GenericContext.h:264-303`): packs interleave with ordinary generic
  arguments in the ordinary generic-argument vector, distinguished by a *separate*
  trailing table of shape descriptors (kind: metadata pack vs. witness-table pack, index,
  shape-equivalence class). Decoding a pack-shaped generic signature means walking two
  parallel structures, not just reading one flat argument list the way
  `GenericNominalTypeResolution.swift` does today for ordinary generics.
- **Dynamic, not static, arity.** A pack's length is a *runtime value* (`PackLength`),
  not something bakeable into a fixed-arity Swift closure the way every other requirement
  kind in this codebase is handled (`StubRequirementKind`, `CallableRequirementDescriptor`,
  the whole call-frame/trampoline argument model all assume a fixed, compile-time-known
  argument count per requirement). A pack-shaped requirement needs the *trampoline itself*
  to iterate a runtime-determined number of stack/register slots and build a
  correspondingly-sized `[Any]` — a structurally different code path from every other
  argument-decoding path in `RuntimeArgumentDecoder`/`TrampolineCallFrame`.
- **Metadata packs and witness-table packs are heap- or stack-allocated on demand**
  (`GenPack.h`'s `cleanupTypeMetadataPack`, `cleanupWitnessTablePack`,
  `cleanupStackAllocPacks`, `deallocatePack` — allocation/cleanup is a first-class,
  non-trivial part of the ABI, not a fixed struct layout to memcpy). Fabricating a
  witness that needs to *hand back* pack metadata (e.g. an associated-type-in-a-pack
  scenario) would mean replicating this allocation/cleanup discipline, including its
  interaction with `swift_task_alloc`-style stack discipline this repo already leans on
  elsewhere for coroutines.
- **IRGen lowering is spread across parameter passing, pack expansion inside tuples,
  and structural pack component indexing** (`emitIndexOfStructuralPackComponent`,
  `bindOpenedElementArchetypesAtIndex`, `emitWitnessTablePackRef`) — a full calling
  convention on its own, layered on top of (not instead of) the ordinary Swift calling
  convention this repo already reverse-engineers.

None of this is a "flip a flag" addition. It's a second, parallel argument-passing model
that has to compose with everything the trampoline already does (indirect results,
`swiftself`/`swifterror`/`swiftasync`, generic requirement arguments, coroutine yields).

## Proposed incremental path (if this is ever picked up)

Rather than "implement full pack support" as one undertaking, split it:

1. **Demangling/signature-discovery support first, dispatch later.** Extend
   `DemangledTypeSyntax`/`WitnessSignatureParser` to *parse* a `"repeat <T>"` parameter
   spelling into a distinct case (instead of failing at `DemangledTypeSyntax(spelling)`
   returning `nil`), so discovery can at least produce a structured, better error message
   ("requirement N has a parameter-pack parameter, which isn't supported yet") instead of
   the current generic "could not resolve runtime metadata" message. This is a small,
   safe, immediately shippable improvement independent of the rest.
2. **Fixed small pack arities as a deliberately bounded first slice.** Rather than
   general dynamic-arity dispatch, support only pack requirements the *conforming type*
   instantiates at a small, fixed length (e.g. 0-4 elements) discovered per-conformance,
   reusing the existing fixed-arity trampoline machinery N times instead of building
   genuine dynamic iteration. This sidesteps the hardest part (arbitrary runtime arity)
   at the cost of a documented, fail-closed ceiling — consistent with how this repo
   already bounds generic-accessor argument counts (`GenericNominalTypeResolution.swift`'s
   3-direct-argument cap) as a pragmatic, not ABI-mandated, limit.
3. **General dynamic-arity pack dispatch is the real "very high effort" remainder** —
   requires the trampoline to allocate and iterate a pack of unknown-at-compile-time
   length, which is new territory for this codebase's whole architecture (every other
   requirement kind assumes the call frame's shape is knowable once the requirement is
   discovered). This should stay unimplemented until steps 1-2 prove out real demand.

## Recommendation

Do not attempt this now. Step 1 above (better diagnostics) is the only piece worth
doing without a concrete driving use case, and it's small enough to fold into ordinary
signature-discovery hardening rather than treated as part of "pack support." The rest is
correctly scoped as future work, gated on someone actually needing it.

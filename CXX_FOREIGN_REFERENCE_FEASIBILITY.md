# Copyable C++ Foreign Reference Support — Feasibility Finding

Status: **blocked**, verified by reproduction, not implementable today. This is not a
TestDoubles design limitation — it's an incompatibility in the vendored `Echo`
dependency that surfaces the moment a real consumer needs both C++ interop and
TestDoubles in the same build.

## What was checked

Swift's C++ interop support does let a class be imported as a reference type instead of
being flattened into a value type:

```cpp
class __attribute__((swift_attr("import_reference")))
      __attribute__((swift_attr("retain:immortal")))
      __attribute__((swift_attr("release:immortal")))
Widget {
public:
  int value() const { return 42; }
};
```

Echo already has a typed wrapper for this metadata kind
(`.build/checkouts/Echo/Sources/Echo/Metadata/ExtendedExistentialMetadata.swift:387`,
`public struct ForeignReferenceTypeMetadata: Metadata, LayoutWrapper`), and TestDoubles
already has a slot in its metadata-kind dispatch where a new case could go
(`Sources/TestDoubles/Metadata/ExtendedExistentialMetadata.swift`'s
`inspectStubProtocolMetadata` switch, and the `.foreignClass`/`.class`/`.objcClassWrapper`
groupings already present in `RuntimeValueLayout.swift` and
`FunctionPointerAuthentication.swift`). So the Swift-side pieces to *recognize* the kind
exist.

**A standalone package with a C++ interop target compiles fine on this machine** —
verified with a minimal `Widget` class above, imported into a Swift target with
`.interoperabilityMode(.Cxx)`, conforming it to a Swift protocol, and calling the
protocol method through an existential. No problem there.

**The actual blocker appears the moment that same consumer target also depends on
TestDoubles.** Reproduced directly:

```
error: could not build Objective-C module 'CEcho'
.../CEcho/include/Builtins.def:33:1: error: variable has incomplete type 'void'
BUILTIN(RawPointer, Bp)
  ...expanded from macro 'BUILTIN'...
  extern void $sBpN;
```

Swift's C++ interop mode is a property of the *importing* Swift target: once a target
sets `.interoperabilityMode(.Cxx)`, every C/Objective-C header it imports — including
transitively, through every dependency — gets reparsed as C++, not C. Echo's `CEcho`
target generates tentative `extern void $sSYMBOLN;` declarations for every builtin type
in `Builtins.def`, to reference runtime-defined metadata symbols by name. A
tentative-definition `extern void x;` is legal C (an incomplete-type declaration that's
never referenced as a value) but is flatly illegal in C++ (`void` variables can't exist
at all). The moment any target that needs `TestDoubles` also needs
`.interoperabilityMode(.Cxx)` for its own C++ types, `CEcho` fails to build as a C++
header, and the whole target fails before TestDoubles' own Swift code is even reached.

This was reproduced two ways: first with a hand-rolled probe package depending on Echo
directly, then conclusively with a probe package depending on the real local
`swift-test-doubles` checkout via a path dependency, with `.interoperabilityMode(.Cxx)`
on the consuming executable target. Both fail identically at `CEcho`.

## Why this isn't fixable inside TestDoubles

TestDoubles' own Swift code never needs to `import` a consumer's C++ header — witness
fabrication operates entirely on type-erased `Any.Type`/`UnsafeRawPointer`, so nothing
here requires `.interoperabilityMode(.Cxx)` on TestDoubles' own targets. The break is
purely that **Echo**, a vendored dependency pinned via `Package.resolved` (currently
`0.1.16`), ships a C shim that isn't valid under C++ parsing rules. That's upstream of
this repository. Patching it would mean either:

- Forking or patching Echo's `Builtins.def`/`KnownMetadata.h` (e.g. wrapping the
  `BUILTIN` macro's declarations in `#ifdef __cplusplus extern "C" { ... } #endif`, or
  giving them a real type instead of `void`) and getting that upstream or vendored in, or
- Isolating every Echo import behind a boundary that never gets reparsed under a
  C++-interop target's language mode — not possible with SwiftPM's current module system,
  since the reparse follows the *importing* target, not the *declaring* one.

Neither is something to do unilaterally inside this repository: the first changes a
pinned external dependency's public C shim (needs to happen in Echo, or as a deliberate,
visible fork with its own maintenance cost); the second isn't achievable with today's
SwiftPM/Clang-importer model at all.

## What would still need to be built, if the blocker were lifted

For completeness — this is what's *actually* missing on the TestDoubles side, so the
work is scoped even though it isn't happening now:

1. A new branch in `inspectStubProtocolMetadata`/witness-table fabrication for the
   `.foreignReference` (or whatever Echo's `ForeignReferenceTypeMetadata` kind maps to)
   case, alongside the existing `.class`/`.foreignClass` handling.
2. Calling-convention treatment for methods on a foreign reference Self: these types are
   always reference-counted by the user-supplied `retain:`/`release:` functions (or
   `immortal`, meaning no-op), never by Swift ARC directly — the trampoline's retain/
   release assumptions (`swift_retain`/`swift_release` calls baked into
   `TestDoublesTrampoline.c`) would need a path that *doesn't* call those for a foreign
   reference Self, since the user's own retain/release functions own that.
3. Move-only foreign reference forms are explicitly out of scope per the request (Swift
   doesn't support them as protocol-conforming types in the same way yet, and doing so
   would compound with the still-unimplemented general noncopyable-value support — see
   `NONCOPYABLE_RECORDER_DESIGN.md`).
4. New fixtures under a C++-interop-enabled test target — which itself can't be added to
   this package's existing test suite without hitting the exact `CEcho` blocker above,
   so any real test coverage would need to live in a separate sibling package until the
   Echo incompatibility is resolved.

## Recommendation

Don't implement item 8 now. The most valuable next step is reporting the `CEcho`/C++
incompatibility to Echo's maintainer (or filing a fork with the minimal fix) — that's
the actual unblock, and it's small in isolation (an `#ifdef __cplusplus` guard or a
typed dummy symbol instead of `void`). Once that lands, the TestDoubles-side work above
is a well-scoped, medium-effort addition, not a research problem.

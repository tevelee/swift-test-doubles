# Copyable C++ Foreign Reference Support — Feasibility Finding

Status: **unblocked, pending a one-line dependency fix.** The blocker is real and
reproducible, but it is *not* external: it lives in `github.com/tevelee/Echo`, this
project's own fork of Echo. A minimal fix has been written and verified end to end (see
"The fix" below); it just needs to land in that fork and be picked up by a version bump
here. The TestDoubles-side feature work is then a well-scoped, medium-effort addition
rather than a research problem.

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
(`Sources/TestDoublesRuntimeMetadata/Metadata/ExtendedExistentialMetadata.swift`'s
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

## Why it can't be fixed inside *this* repository

TestDoubles' own Swift code never needs to `import` a consumer's C++ header — witness
fabrication operates entirely on type-erased `Any.Type`/`UnsafeRawPointer`, so nothing
here requires `.interoperabilityMode(.Cxx)` on TestDoubles' own targets. The break is
purely that **Echo** ships a C shim that isn't valid under C++ parsing rules. Isolating
the Echo import behind some boundary that never gets reparsed isn't possible with
SwiftPM's current module system, because the reparse follows the *importing* target, not
the *declaring* one. So the change has to happen in Echo.

The good news: `Package.swift` depends on `https://github.com/tevelee/Echo.git` — this
project's own fork — so "upstream" here is a repository this project controls, not a
third party.

## The fix

Two lines of real change in `Sources/CEcho`, verified end to end:

```diff
--- a/Sources/CEcho/include/KnownMetadata.h
+++ b/Sources/CEcho/include/KnownMetadata.h
 #define BUILTIN(NAME, SYMBOL) \
-extern void $s##SYMBOL##N;
+extern char $s##SYMBOL##N;

--- a/Sources/CEcho/KnownMetadata.c
+++ b/Sources/CEcho/KnownMetadata.c
 void *getBuiltin##NAME##Metadata(void) { \
-  return &$s##SYMBOL##N + sizeof(void*); \
+  return (void *)(&$s##SYMBOL##N + sizeof(void*)); \
 }
```

Both of the original constructs are GNU C extensions that C++ rejects: `extern void x;`
(a variable of incomplete type `void`) and `void*` pointer arithmetic (`&x + n`, which
GNU C treats as byte arithmetic). Declaring the symbol `char` fixes both at once — the
address is identical, `char*` arithmetic is byte arithmetic by definition in both
languages, and the emitted undefined symbol reference is unchanged because an `extern`
declaration's type never reaches the linker. Only the explicit `(void *)` cast is added,
since C++ won't implicitly convert `char*` to `void*` on return.

Verified on this machine, all three of:

1. **Echo still builds and its own test suite passes** — 84 tests, no failures.
2. **The previously-failing C++ scenario now works** — the probe package that used to die
   at `could not build Objective-C module 'CEcho'` now builds, and at runtime both the
   imported C++ foreign reference type (`Widget().value()` → `42`) and Echo reflection
   (`reflect(Int.self).kind` → `struct`) work from the same `.interoperabilityMode(.Cxx)`
   target.
3. **TestDoubles is unaffected** — full suite (893 tests) passes against the patched Echo
   via a local `swift package edit` override, then the override was removed and the pin
   restored.

The patch has deliberately **not** been pushed to the Echo fork — that's a separate,
published repository, and landing a change there plus bumping the version pin here is a
call for the maintainer to make, not something to do as a side effect of this
investigation.

## What still needs to be built on the TestDoubles side

The dependency fix above only unblocks the build. This is the actual feature work, still
to do:

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
4. New fixtures under a C++-interop-enabled test target. Note this is only possible
   *after* the Echo fix lands — before it, such a target cannot build at all, which is
   why no test coverage for this feature exists or can be added today.

## Recommendation

Two steps, in order:

1. **Land the two-line `CEcho` fix in `tevelee/Echo` and bump the pin here.** This is
   worth doing on its own merits, independent of whether the foreign-reference feature
   ever gets built: today *any* consumer that enables Swift/C++ interop anywhere in its
   dependency graph cannot use TestDoubles at all, for reasons that have nothing to do
   with C++ foreign reference types. That's a silent, hard-to-diagnose adoption blocker
   affecting an entire class of mixed-language projects, and the fix is verified.
2. **Then** decide whether the foreign-reference feature itself is worth the
   medium-effort work listed above, which is only a real option once step 1 makes it
   testable.

# Copyable C++ Foreign Reference Support — Feasibility Finding

Status: **build blocker resolved; the feature itself is still unbuilt.** Consuming C++
interop alongside TestDoubles used to be impossible for reasons unrelated to foreign
reference types. That is fixed: Echo `0.1.17` makes the `CEcho` shim parse as C++, and
this package now pins it. What remains is the actual foreign-reference feature work
listed under "What still needs to be built" below — now a well-scoped, medium-effort
addition rather than a research problem, and testable for the first time.

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

## The fix (landed in Echo 0.1.17)

Two lines of real change in `Sources/CEcho`:

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

Verified before release:

1. **Echo's own test suite passes** — 84 tests on both Swift 6.2 (that checkout's default)
   and Swift 6.3.3 (this package's pinned toolchain).
2. **TestDoubles is unaffected** — full suite (893 tests), lint, and the wasm32 validation
   all pass against Echo `0.1.17`.
3. **The previously-impossible scenario now works end to end** — a probe package that
   enables `.interoperabilityMode(.Cxx)` and depends on TestDoubles used to fail at
   `could not build Objective-C module 'CEcho'` before reaching any of its own code. It
   now builds and runs, exercising both halves in one target: the imported C++ foreign
   reference type (`Widget().value()` → `42`) and runtime stub fabrication
   (`Stub<any Greeter>` returning a configured `7`).

Note that (3) demonstrates the *build* blocker is gone and that ordinary TestDoubles
stubbing works from a C++-interop target. It does **not** mean C++ foreign reference
types can be used as stub `Self` types yet — that's the unbuilt feature work below.

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

## Status and next step

**Done:** the `CEcho` fix shipped as Echo `0.1.17` and this package pins it. That was
worth doing on its own merits, independent of the foreign-reference feature: before it,
*any* consumer enabling Swift/C++ interop anywhere in its dependency graph could not use
TestDoubles at all, failing on a header with no apparent connection to their own code —
a silent, hard-to-diagnose adoption blocker for every mixed-language project.

**Open:** whether the foreign-reference feature itself is worth the medium-effort work
listed above. It's now a real option rather than a blocked one, and testable for the
first time, but it remains unbuilt and unscheduled.

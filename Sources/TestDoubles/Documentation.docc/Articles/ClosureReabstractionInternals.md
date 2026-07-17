# Closure Reabstraction Internals

Understand how TestDoubles moves native Swift closure values across the
recorder's generic `Any` boundary without protocol annotations, generated
forwarders, or access to the protocol source.

## Overview

### Why reabstraction is necessary

A native Swift closure value is two words: a function entry point and a retained
context. Those two words do not, by themselves, describe how to call the entry
point. The calling convention comes from the function's runtime metadata.

The same source-level closure type has two relevant lowered representations:

- The **direct representation** is used by ordinary compiled Swift code. Values
  may occupy general-purpose or floating-point registers, large values may be
  passed indirectly, and direct results may use return registers or the
  indirect-result register.
- The **generic representation** is used after the closure crosses generic
  storage such as `Any`. Explicit parameters are addresses of values and a
  non-`Void` success result is written through an `@out` address. Typed errors
  have their own generic `@error @out` convention.

Calling a direct entry point with the generic convention, or the reverse, is
undefined even when the printed Swift types are identical. Reabstraction is the
adapter between these conventions.

TestDoubles needs both directions:

```text
protocol closure argument
    direct function + direct arguments
        -> generic recorder value

configured closure result
    generic recorder value
        -> direct function + direct result
```

### Choose a bridge without source access

Automatic construction begins with canonical `FunctionMetadata` discovered
from the protocol signature. The metadata supplies the convention, parameter
and result types, parameter flags, effects, `@Sendable`, global-actor and
extended-function flags, and the concrete typed-error metadata when present.

For eligible synchronous and async native closures, TestDoubles builds a
bounded dynamic bridge. This is the preferred path and does not require a
matching reabstraction symbol in the final image. An exact pair of
compiler-emitted direct-to-generic and generic-to-direct thunks remains the
fallback for isolated, ownership-qualified, variadic, sending, and other
extended shapes.
`@convention(c)` and `@convention(block)` values use their ordinary value
witnesses and need no native Swift reabstraction.

The dynamic path validates the complete shape before retaining a closure or
publishing an entry point. Unknown extended bits, noncopyable values, parameter
flags whose invocation semantics are not reproduced, unresolved nested
functions, and register overflow all fail during stub construction.

### Adapt a direct argument into generic storage

When a protocol call supplies a closure argument, the witness trampoline has a
direct closure pair. The direct-to-generic bridge performs these steps:

1. Read the function and context words from the incoming value and retain the
   context for the transported closure's lifetime.
2. Open the runtime result type, each runtime parameter type, and, for typed
   throws, the concrete `Failure: Error` type.
3. Instantiate a fixed-arity Swift wrapper whose source type exactly preserves
   `@Sendable`, `async`, `throws`, or `throws(Failure)`. Fixed arities from zero
   through six are used because Swift cannot reliably erase a variadic function
   type to `Any`.
4. When invoked, turn each generic wrapper argument into prepared direct
   storage. Nested functions, tuples, and optionals are recursively converted
   to their direct representation.
5. Classify each prepared value with the native ABI classifier, populate a
   `TDCallFrame`, and call the original function/context pair through the fixed
   assembly invoker.
6. For async closures, allocate a child async context from the source
   descriptor, preserve the caller continuation, and resume only after the
   source closure completes.
7. Decode the direct success or error result and move it into the Swift
   wrapper. Converting that wrapper to `Any` lets Swift produce its canonical
   generic function representation.

The assembly invoker is intentionally type-independent. It restores the
general-purpose, floating-point, indirect-result, closure-context, and Swift
error registers described by the call frame, calls the entry point, then
captures the corresponding return state. On pointer-authenticated arm64, the
entry point is called with the discriminator reconstructed from the canonical
function metadata.

Prepared arguments own initialized copies until the invocation completes.
Owned direct results and typed errors are moved exactly once. Uninitialized
success storage is never destroyed after a failed call.

### Adapt a generic result into a direct closure

A closure returned by a configured handler is stored in generic form. To return
it to compiled protocol code, TestDoubles creates a new direct closure pair:

- A synchronous function word points to `td_swift_dynamic_function_entry`. An
  async function word points to a Swift async descriptor whose relative entry
  reaches the shared async trampoline. The word is signed with the appropriate
  code or data key and direct function discriminator when pointer
  authentication is active.
- The context owns the generic source function/context pair, the exact function
  metadata, and all derived layouts.

When compiled code invokes this returned closure, the dynamic entry captures
the direct call in a `TDCallFrame` and enters the metadata-aware Swift handler.
The handler:

1. Decodes direct parameters in their GP, FP, aggregate, or indirect layouts.
2. Boxes the values into recorder-owned generic storage, recursively
   reabstracting nested function values where required.
3. Projects each generic value container and passes its address in one generic
   argument register.
4. Supplies the generic success `@out` address and any generic typed-error
   `@error @out` address.
5. Calls the generic source function through the matching synchronous or async
   assembly invoker. The async path keeps the frame and prepared values alive
   across suspension.
6. Boxes and destroys the initialized generic result, then initializes the
   direct result registers or caller-owned buffer expected by the original
   closure caller.

The returned closure context retains the generic source context until the last
copy of the returned direct closure is released.

### Keep typed-error transports distinct

Typed throws does not use a heap-allocated `Swift.Error` object. The Swift error
register is an outcome discriminator: zero means success and one means a typed
failure. The concrete failure payload travels separately.

There are two related but distinct layout decisions:

| Boundary | Success transport | Typed-error transport |
| --- | --- | --- |
| Direct closure | Native return registers, or the indirect-result register | GP return registers when the error is a direct integer-class value; otherwise a distinct caller-owned typed-error slot |
| Generic closure | A non-`Void` `@out` address | A distinct `@error @out` address for every nonempty error value |

For the direct convention, TestDoubles consumes a typed-error slot when the
success result is indirect, the error itself is indirect, or the error's direct
layout needs floating-point return state. Pure GP error aggregates that fit the
supported return-register budget stay direct. For the generic convention, a
nonempty error always receives its own output buffer even when that same value
could be directly returned in several registers. A zero-size error has no
physical payload slot.

These rules explain an otherwise surprising case: a 32-byte integer error can
return directly in four GP registers from a direct closure, yet its generic
representation still receives an `@error @out` buffer. Conversely, a mixed
`Int`/`Double` error is written indirectly on the direct side because typed
error transport cannot publish that mixed payload through the ordinary direct
error registers.

Any hidden typed-error address follows the explicit arguments in the
general-purpose argument sequence. It is not the success indirect-result
address. The dynamic bridge reserves and validates both independently, and the
reverse bridge distinguishes the direct caller's error destination from the
generic source function's error destination.

Untyped `throws` is different: a nonzero Swift error register contains a
retained Swift error object. The bridge extracts and releases that object after
boxing its concrete payload. Treating the typed value `1` as an error-object
pointer would crash, so the metadata decides the error path before the register
is interpreted.

### Recurse through higher-order values

Reabstraction is structural where runtime layout is knowable. A function
parameter or result is recursively bridged. Tuple elements and `Optional`
payloads are visited in place. Public nominal and generic containers use
resolved metadata plus value witnesses; exported generic descriptors are
supported when their runtime key arguments do not require additional witness
table arguments.

Opaque containers such as arrays, dictionaries, `Result`, and public enums keep
their native value representation. Their metadata and value witnesses preserve
the payload, while any closure that later reaches an explicit callable boundary
is reabstracted there. Unknown private layouts and constrained generic metadata
that needs unavailable witness arguments fail closed.

### Preserve contexts and special registers

Both source closure contexts are retained explicitly. Temporary value buffers
are aligned with their runtime value-witness requirements and are initialized,
moved, destroyed, and deallocated according to which outcome actually
occurred. Caller-provided success and error buffers remain caller-owned.

The Swift closure context register and Swift error register are independent.
For nonthrowing synchronous closures, the error register is callee-saved state
and must be preserved rather than cleared. A nonthrowing async completion does
not promise meaningful error-register contents, so the inverse async invoker
ignores that register unless metadata says the closure throws. Throwing bridges
publish zero, a typed-error discriminator, or an untyped Swift error object as
appropriate.

### Bounded dynamic ABI

The dynamic direct-to-generic bridge supports zero through six formal
parameters. The generic-to-direct bridge has eight generic argument registers
on arm64 and six on x86-64. Both sides also validate the actual GP and FP
consumption, including hidden typed-error slots, and currently reject layouts
that would spill closure parameters to the stack.

Global actors, `@isolated(any)`, `nonisolated(nonsending)`, sending
parameters/results, ownership-qualified or variadic parameters, differentiable
functions, noncopyable values, and unknown extended metadata continue to
require an exact compiler-emitted reabstraction pair. Ordinary async closures,
including untyped and typed throws, are part of the bounded source-less path;
extended async executor semantics remain fail-closed without an exact thunk.

See <doc:FunctionValues> for the public support matrix and
<doc:TrampolineArchitecture> for the surrounding witness-call machinery.

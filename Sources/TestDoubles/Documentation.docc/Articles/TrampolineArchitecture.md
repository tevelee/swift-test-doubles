# Trampoline Architecture

See how one fixed runtime trampoline dispatches arbitrary supported protocol
witness calls to a stub recorder.

## Overview

`Stub<P>` creates an existential whose witness entries point to small
architecture-specific veneers. Each veneer supplies a requirement index and
branches to a shared assembly trampoline. The trampoline preserves the incoming
register state, asks Swift code how to handle the call, then restores the return
state expected by the caller.

This design keeps the package small: TestDoubles does not emit Swift source,
compile a conformer, or generate a matrix of typed thunks for each protocol.

## Construction

Construction has two signature sources:

1. With no explicit requirements, TestDoubles finds a linked conformance,
   copies its witness table, and discovers function metadata from its entries.
2. With typed ``Stub/Requirement`` values, TestDoubles fabricates a payload
   type and witness table directly.

Both paths normalize into internal method descriptors containing the
requirement index, kind, effects, argument metadata, and return metadata. The
same veneer and recorder path handles both.

Explicit requirements are validated against the protocol descriptor before
memory is allocated. Requirement order matters because a Swift witness table is
positional.

## Invocation

For a synchronous call, the trampoline:

1. Captures general-purpose, floating-point, and stack argument state.
2. Uses the veneer index to find the method descriptor and owning recorder.
3. Decodes arguments from runtime metadata.
4. Records the call and selects the most specific configured response.
5. Encodes the result or Swift error into the caller's expected ABI state.

For an async call, the entry trampoline preserves the caller continuation,
creates a Swift task continuation around recorder dispatch, and resumes through
an architecture-specific continuation trampoline. The configured handler runs
on the caller's task, preserving task-local values, cancellation, priority, and
executor context.

## Ownership and concurrency

The owning `Stub` retains the payload metadata, witness-table allocation,
veneers, and recorder. A fabricated existential must not outlive that owner.

Recorder state is lock-protected so calls may arrive concurrently after serial
configuration. Matchers and handlers are selected from a snapshot; user code is
not executed while the recorder lock is held.

## Supported ABI boundary

The implementation has focused arm64 and x86_64 coverage for integer and
floating-point registers, stack arguments, mixed aggregates, indirect results,
throwing calls, and async continuations. Construction rejects function-valued
requirements because safe closure reabstraction needs compiler-emitted code.

The remaining x86_64 six-integer async boundary and custom-executor validation
are tracked in the roadmap's runtime-hardening iteration.

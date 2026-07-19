# How Runtime Stubs Work

Take a high-level tour of the runtime machinery that turns a ``Stub`` into a
working protocol value.

## Overview

When you create a `Stub<any Service>`, TestDoubles does not generate Swift
source, compile a conforming type, or modify the protocol. It builds a small,
private conformance at runtime and packages it into an ordinary protocol
existential.

To calling code, that value behaves like any other value of `any Service`.
Behind the existential, a recorder stores configured behaviors and observed
calls. A trampoline connects the two worlds: it receives a protocol witness
call in Swift's native calling convention and turns it into a recorder
operation that can match arguments, run a handler, and return a value.

The complete path looks like this:

```text
protocol call
    → fabricated witness table
    → per-requirement veneer
    → shared assembly trampoline
    → Swift decoder and recorder
    → configured behavior
    → Swift encoder
    → original caller
```

### Start with Swift's protocol dispatch

A protocol existential contains a value together with witness tables. A witness
table is the set of entry points Swift uses to fulfill the protocol's
requirements. When code calls a method through an existential, it looks up the
corresponding entry and calls it.

TestDoubles takes advantage of that existing dispatch mechanism. During
construction it:

1. Reads the protocol layout and discovers the callable signatures.
2. Validates that every requirement fits the supported runtime boundary.
3. Creates a recorder for behaviors and invocations.
4. Allocates private witness tables and fills their callable entries with
   trampolines.
5. Places those tables and an owning payload into the generated existential.

Signatures can come from a real conformance already linked into the process,
from exported resilient-protocol descriptors, or from explicit
``Stub/Requirement`` values. These sources describe the same protocol calls;
they only differ in where TestDoubles obtains the facts needed to build the
runtime representation. See <doc:ConstructionGuide> for the construction
choices.

The fabricated conformance belongs only to the returned existential. It is not
registered as a process-wide conformance and does not replace any real
implementation.

### Follow a call through the trampoline

Each witness entry points to a small executable veneer. The veneer identifies
the requirement and the witness table that owns it, then branches to a shared
assembly entry point. Keeping the veneers small allows many different protocol
requirements to reuse the same core machinery.

The shared trampoline captures the incoming general-purpose registers,
floating-point registers, and relevant stack state in a call frame. Swift code
then uses the captured requirement identity to find its method description and
recorder. Runtime type metadata tells the decoder how to turn the native
arguments into values the recorder can inspect.

In normal operation, the recorder evaluates configured matchers, then enters a
post-matcher dispatch linearization point that commits matcher captures, appends
the invocation, and reserves a sequenced behavior atomically. It then runs the
selected return value or handler. The result encoder performs the reverse
operation: it places the result, or a thrown error, into the registers and
buffers expected by the original caller. The trampoline restores that return
state and completes the witness call.

Async requirements follow the same model while also preserving the caller's
continuation across suspension. Read-write properties and subscripts use a
specialized `_modify` path that yields temporary storage and writes the final
value back through the configured setter. Function-valued arguments and results
may need an additional reabstraction step because a concrete Swift closure and
an `Any`-based recorder do not necessarily use the same calling convention.
These are adaptations around the same central recorder path, not separate
mocking systems.

### Configuration uses the same path

A `when` closure is not analyzed as source code. TestDoubles temporarily puts
the recorder into capture mode and invokes the closure with the generated
protocol value:

```swift
stub.when { $0.load(id: any()) }.thenReturn("sample")
```

The apparent call to `load(id:)` travels through the same witness table and
trampoline as a real call. In capture mode, however, the recorder saves the
requirement and its matchers without running a behavior or adding a normal
invocation. It returns a safe recording placeholder so the closure can finish.
`thenReturn` attaches the behavior to that captured call description.

Verification repeats the capture step to describe an expected call, then
compares that description with the recorder's call log. Capture state is scoped
to the current task, so an unrelated concurrent invocation remains a normal
call. Eventual verification waits on call-log generation changes rather than
polling. Successful verification records stable call identities for
`verifyNoMoreInteractions()` without consuming the log. This is why the public
configuration and verification APIs can use natural protocol calls without
macros or generated conformers.

### Keep the generated value alive

The existential's private payload owns its recorder, witness tables, page-backed
executable veneer arena, and related allocations. A generated protocol value
can therefore outlive the ``Stub`` that created it. When the last owning value
is released, its recorder is unregistered and its executable veneer pages are
unmapped. Witness allocation has a transactional boundary: a construction that
fails before the generated existential is complete releases its temporary
descriptor and table allocations. Successful construction commits that witness
identity, whose small allocation keeps a process-stable address because Swift's
generic-metadata caches may still refer to it after the payload is gone.

Recorder state is protected for calls that arrive concurrently after
configuration. Configuration and verification are intentionally serial because
both use the recorder's temporary capture mode. Keep those APIs on one
isolation domain. A generated value whose protocol is `Sendable` may cross
domains only when every configured value, matcher or captor state, and handler
capture is safe to share.

### Fail closed at the runtime boundary

The trampoline must follow Swift's actual calling conventions. Argument
registers, indirect results, ownership, throwing, async continuations,
coroutines, and function reabstraction all affect how a requirement crosses the
boundary. TestDoubles supports a deliberately tested set of these shapes on
arm64 and x86-64.

Construction rejects a shape when the library cannot discover or represent it
safely. It does not infer a signature from nearby memory or attempt a best-effort
call. This fail-closed behavior turns an unsupported runtime shape into an
explicit construction error instead of memory corruption or a subtly incorrect
test.

For the precise supported boundary, see <doc:StubContract>. For the ABI-level
details, including call frames, witness-table fabrication, ownership, async
continuations, and debugger entry points, continue with
<doc:TrampolineArchitecture>. The two closure calling conventions and both
dynamic adapter directions are documented in
<doc:ClosureReabstractionInternals>. ``Dummy`` uses the same private conformance
machinery, but routes every invocation to an intentional failure instead of a
configurable recorder; see <doc:DummyTestDoubles>.

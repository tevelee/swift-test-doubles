# Trampoline Architecture

See how one fixed runtime trampoline dispatches arbitrary supported protocol
witness calls to a stub recorder.

## Overview

`Stub<P>` creates an existential whose protocol witness entries point to small
architecture-specific veneers. Each veneer supplies a dense dispatch index and
branches to a shared assembly trampoline. The trampoline preserves the incoming
register state, asks Swift code how to handle the call, then restores the return
state expected by the caller.

This design keeps the package small: TestDoubles does not emit Swift source,
compile a conformer, or generate a matrix of typed thunks for each protocol.

### Construction

Construction has three signature sources:

1. Automatic discovery prefers linked conformances and discovers function
   metadata from witness thunk symbols while following inherited witness
   tables.
2. Without a linked conformance, a resilient protocol can expose an exported
   method descriptor symbol at each ABI requirement record. TestDoubles accepts
   only an exact-address `Tq` symbol and demangles its signature. The protocol
   metatype itself is only the route to these records; it is not a signature
   source.
3. With typed ``Stub/Requirement`` values, the caller supplies a flat
   base-first sequence for one root. A composition instead uses
   ``Stub/ProtocolRequirements`` groups keyed by bare declaring protocols.

Both paths normalize into one fully typed internal method descriptor containing
the requirement index, kind, effects, argument metadata, and return metadata.
Automatic discovery must resolve all of that metadata before allocation. Every
path then fabricates the same private class payload and witness-table graph,
using the same descriptors, veneers, and recorder path. Missing or stripped
requirement symbols are not guessed from neighboring addresses.

The protocol layout walks bases depth-first and keeps the first occurrence of a
shared base. Witness slots remain local to their declaring protocols, while
dispatch indices are dense across the complete graph. Explicit requirements are
validated against that layout before memory is allocated. Composition group
order does not affect layout; order inside a group remains positional. When a
linked conformance is available, every reliably discoverable signature
component is compared as well. Getter throwing behavior remains caller-supplied.

Fabrication allocates one witness table for each unique protocol node, installs
base-table links, and writes one root table per composition component into the
existential container. Every table context maps to the same recorder.

A synchronous explicit requirement containing a direct function value takes a
separate typed path. Its witness entry points to a veneer that preserves the
incoming arguments, inserts a retained ``Stub/Invocation`` in the next unused
general-purpose argument register, and tail-calls a caller-supplied
`@convention(thin)` function. That compiler-emitted function has the native
witness argument, result, and error ABI; no closure pointer enters the untyped
call frame.

An ordinary opaque existential stores the private class payload in its value
buffer. A class-constrained existential instead stores the payload object
reference directly, followed by the root witness-table pointers. A supported
superclass-constrained existential uses the same reference layout but stores a
genuine instance of its `NSObject`-backed superclass. An associated private
payload retains the recorder and fabricated allocations. Fabricated conformance
descriptors identify Swift-defined classes through an indirect type-context
descriptor and imported Objective-C classes through a direct runtime class
name. Objective-C-only protocol layouts are still rejected before allocation.

A constrained `any Protocol<Concrete>` existential uses extended existential
metadata. The bounded associated-type path validates the exact generic binding
shape, maps every concrete metadata argument to its declaring protocol and
associated-type name, and checks that mapping against the flattened inheritance
and composition graph. It installs the associated metadata and direct
conformance witnesses. Direct associated arguments and results, and dependent
`Optional` values, lower indirectly even when their bindings are register-sized;
dependent `Array`, `Set`, and `Dictionary` values retain their ordinary direct
reference layout while remaining dependent for signature validation. Dictionary
dependencies preserve whether the key, value, or both came from an associated
type. Opaque and class-constrained extended existentials use their respective
container layouts. An associated
type constrained to `AnyObject` has a different dependent reference ABI and is
rejected before witness fabrication.

An ordinary unbound `any Protocol` existential does not carry concrete
associated metadata. Caller-bound construction validates an explicit mapping
from declaring protocol plus associated-type name to concrete metadata, then
installs that mapping in the same fabricated structural witness entries. This
reuses dependent indirect-result lowering for covariant method and getter
results, and supplies the indirect error metadata for a direct associated typed
error. Swift erases dependent success calls to the associated type's upper
bound, so the runtime dynamically casts the configured result back to the bound
concrete type before initializing the indirect return buffer. Associated inputs
stay fail-closed because the unbound existential interface cannot express them.

### Invocation

For a synchronous call, the trampoline:

1. Captures general-purpose, floating-point, and stack argument state.
2. Uses the veneer index to find the method descriptor and owning recorder.
3. Decodes arguments from runtime metadata.
4. Records the call and selects the first configured matching response.
5. Encodes the result or Swift error into the caller's expected ABI state.

The bounded SIMD path classifies only complete 128-bit lane payloads that Swift
6.3 passes in one vector register on both arm64 and x86_64. Argument capture
already preserves all 16 bytes of each `q` or `xmm` register. The decoder now
copies that declared width instead of truncating it to the scalar low word. For
results, the call frame keeps the established four low scalar return words and
adds a separate high word for each; the synchronous entry bridge reconstructs
the four vector registers before returning. This leaves all established frame
field offsets stable while preserving every SIMD lane bit. Construction checks
the location plan for both architectures and rejects any supported vector that
would become a stack argument. It also rejects every shape that would require
scalarized lanes, padding interpretation, aggregate decomposition, associated
metadata substitution, forwarding, or async continuation transport.

Capture mode normally encodes a synthesized recording result so the `when` or
`verify` closure can return safely. `when(returning:_:)` and
`verify(_:returning:_:)` instead carry a caller-supplied result through task-
local context. This supports reference, existential, optional, and other values
for which synthesis would be invalid, without adding mutable capture state to
the recorder.

A direct setter is an ordinary synchronous witness with one `@owned` value and
a `Void` result. Each argument descriptor records borrowed or owned convention
independently, so consuming method arguments and setter inputs move ownership
into the recorder's type erasure exactly once while borrowed arguments are only
copied, including indirect and reference-containing values. Swift
also emits a mandatory `_modify` coroutine for a read-write property or
subscript. Its dedicated veneer captures the caller's coroutine context before
the ordinary arguments, dispatches the paired getter, and yields aligned
metadata-backed storage. The resume function boxes and destroys that storage
exactly once, then writes it back through the paired setter. Both normal and
abort resumes perform writeback because Swift preserves mutations made before
a thrown unwind. Indexed access retains the borrowed indices across the yield
and restores the setter's `[value, indices...]` ABI order.

For an unmatched Spy call, the same outer veneer authenticates and enters the
target's direct `_modify` witness with a retained 32-byte caller frame. It
relays the target's yielded storage directly, then authenticates the target
continuation against that frame and forwards Swift's normal-or-abort flag
exactly once. A matching getter registration stays on the configured storage
path and never enters the target coroutine.

A Swift 6.3 `read` property or subscript instead has one `yield_once_2`
coroutine descriptor and no separate getter slot. Fabrication maps that witness
to a getter-shaped recorder entry, emits the compiler's 16-byte descriptor, and
signs both the descriptor and resume function on arm64e. Dispatch initializes
metadata-backed storage, returns borrowed direct register bits or an indirect
storage address, and keeps the value alive until either resume path releases it.
The resume discriminator is derived from the yielded result type rather than
the fixed `_modify` discriminator.

A static witness uses the same explicit argument and result lowering as its
instance counterpart. Its hidden `Self` value is a metatype rather than an
instance, but recorder lookup still uses the veneer context. Initializer
arguments are owned. An opaque initializer returns dependent `Self` through an
indirect result buffer, while a class-constrained initializer returns an owned
object reference directly. Successful initialization creates a new payload that
retains the existing resource graph; failable initialization writes either that
payload or `nil` using the corresponding `Self?` layout. Associated-type and
supported dependent-container initializer arguments reuse the same owned
argument transport.

A noninitializer dynamic `Self` result uses the same opaque indirect or
class-direct lowering as nonoptional initializer `Self`. Capture mode and a
configured success both allocate a fresh `StubPayload` from the recorder's
resource graph. Optional noninitializer `Self?` uses the same layout and a
specialized outcome that chooses a fresh payload or `nil`. These builders never
accept a payload from user code, so result transport cannot receive a value from
a different fabricated graph.

For an async call, the entry trampoline preserves the caller continuation,
creates a Swift task continuation around recorder dispatch, and resumes through
an architecture-specific continuation trampoline after recorder dispatch
completes. A bounded ingress path also accepts exactly one eight-byte stack
argument word after the arm64 or x86_64 register banks are exhausted. The entry
frame points at that word only while synchronous preparation is running, so the
decoder copies its value before returning a retained suspension state. The
state never reads the saved stack pointer. The Swift handler returns the complete
entry-SP-to-continuation-SP adjustment alongside that state. arm64 rounds the
logical stack area up to its 16-byte boundary; x86_64 rounds down because its
captured first-stack-argument address follows an implicit eight-byte async ABI
slot. Before x86_64 advances the stack pointer, it carries that live slot to the
resumed continuation stack pointer just as a compiler-generated witness thunk
does. Assembly applies the adjustment once on both immediate and suspending
entry exits, never from the completion trampoline. A second spilled word still
fails closed.

The bounded forwarding counterpart accepts one complete concrete eight-byte
general-purpose spill for a nonthrowing instance method. Synchronous
preparation copies that word into retained forwarding state before the outer
entry removes its caller stack. The async invoke helper then reproduces the
compiler's outgoing generic-witness layout. arm64 reserves 32 bytes containing
the visible word, target metadata, witness table, and alignment padding.
x86_64 moves its live implicit slot down by 16 bytes, then writes those three
words at offsets 8, 16, and 24. The target's compiler-generated witness thunk
performs the only transition to the direct-method continuation stack; the
forwarding completion does not adjust it again. Throwing calls, typed-error
destinations, a second spill, split or padded values, SIMD, dependent values,
and async accessors remain outside this slice.

After matcher evaluation, dispatch enters one recorder linearization point that
atomically commits matcher captures, appends the call, and reserves the next
configured sequence behavior. Ordered verification therefore observes this
post-matcher dispatch order, not invocation-entry or handler-completion order.
Recording an ordered expectation list uses capture mode only; handlers are not
selected or replayed. Matching scans a snapshot for a relative subsequence and
commits verification captors only after the complete sequence succeeds.

### Ownership and concurrency

The fabricated existential owns a private class payload, either directly or as
an association on a genuine superclass instance. That payload retains the
registry and allocation owner, which keeps the recorder, witness-table graph,
and veneers alive. Protocol values therefore remain valid after the original
`Stub` is released; destroying the last payload unregisters the recorder,
unmaps its executable veneer pages, and releases the behavior graph. The small
allocation containing each fabricated conformance descriptor and witness table
is committed only after the complete existential is created. Failed
construction deallocates that temporary identity. A committed identity remains
at a process-stable address because Swift's generic-metadata caches may retain
it without retaining the payload. This trades a small allocation for safe cache
identity while reclaiming every unobservable failed-construction allocation.
The fabricated tables travel only in the returned existential; TestDoubles does
not register a process-wide conformance. In particular, erasing a fabricated
class existential to `AnyObject` and dynamically casting it back is unsupported
because the erased value no longer carries those tables.

An extracted existential metatype carries the witness-table pointer but has no
retain/release hook for the fabricated graph. `Stub.withValue(_:)` therefore
keeps an owning generated value alive for scoped metatype use. Escaping that
metatype beyond the operation is unsupported.

Recorder state is lock-protected so calls may arrive concurrently after serial
configuration. Configuration and verification remain serial operations because
they share capture mode. Matchers and handlers are selected from a snapshot;
user code is not executed while the recorder lock is held. Synchronous handlers
and predicates are `@Sendable`. Async handlers intentionally preserve their
creation actor or executor and must be actor-isolated or protect mutable
captures when calls overlap. The generated protocol value may cross concurrency
domains only when its protocol is `Sendable` and every configured fixed or
sequenced behavior payload, matcher or captor state, and handler capture is safe
to share.
Keep the `Stub`, its recording builders, and verification operations on one
isolation domain. A ``StubBehaviorChain`` is conditionally `Sendable` when its
result is, but configuration must finish before matching invocations begin.

### Supported ABI boundary

The implementation has focused arm64 and x86_64 coverage for integer and
floating-point registers, synchronous stack arguments, mixed aggregates,
indirect results, throwing calls, bounded one-register 128-bit SIMD values,
async continuations, one-word async Stub ingress, bounded one-word async Spy
forwarding, and owned setter inputs. Direct concrete
native function values use canonical function metadata plus compiler-emitted
partial-apply reabstraction thunks found in the linked client or a bounded
runtime-built arm64/x86_64 bridge. Arguments are wrapped from direct witness ABI
to generic `Any` ABI before typed handlers receive them; results are wrapped in
the reverse direction before the witness returns. The runtime bridge handles
ordinary synchronous and async closures with zero through six formal arguments, mixed
general-purpose and floating-point registers, direct and indirect aggregates,
untyped errors, concrete typed errors, and recursively bridgeable higher-order
values. Typed closures distinguish the direct caller's typed-error layout from
the generic `@error @out` layout and reserve separate hidden buffers when
required. The reverse direction may use eight generic argument registers on
arm64 and six on x86-64.
It preserves the Swift self and error registers independently, including the
callee-saved error register of a nonthrowing synchronous closure, and carries
async descriptors and child task contexts across genuine suspension. Tuple and `Optional`
results recurse into structural function payloads; nominal containers use their
value witnesses. C function pointers and block values need no native
reabstraction and use ordinary value-witness transport. See
<doc:ClosureReabstractionInternals> for the complete two-direction closure
adapter and typed-error ownership model.
The native wrapper retains both closure contexts, preserves `@isolated(any)`'s
dynamic actor pair, distinguishes async thunk descriptors, and signs generated
function words with Swift's stable discriminator on pointer-authenticated
targets. Public generic nominal metadata can be recovered from exported
descriptors without source annotations when its runtime key arguments need no
additional witness-table arguments. Raw copying remains unsafe for native
closures. Top-level nonescaping, thin, declaration-level consuming or `inout`,
dependent, parameter-pack, and other unsupported function shapes remain on the
explicit-adapter or fail-closed paths described in <doc:FunctionValues>.

Ordinary class constraints and exact concrete primary-associated-type bindings
across inheritance, composition, and opaque or class storage are supported.
That dependent slice includes direct values, `Optional`, `Array`, `Set`, direct
Dictionary key or value occurrences, direct setters, initializer arguments, and
consuming direct or supported-container method arguments. Static requirements,
initializers, direct or optional dynamic
`Self` results, and `_modify` getter/setter materialization are supported across
opaque and class storage. Ordinary `NSObject`-backed superclass constraints
support Swift protocol calls, compositions, static concrete results, and real superclass
members, but not initializer requirements or dynamic `Self` results. Native
Swift-only superclasses, superclass-constrained extended existentials, broader
dependent-value lowering, `AnyObject`-constrained associated types, direct
`Self` arguments, and `read` forwarding or Dummy requirements remain outside
the supported layout.
Ordinary unbound existentials may receive complete caller-supplied bindings for
covariant associated results; this is an injection into the existing dependent
result path, not a new trampoline convention.
The typed-throws convention reuses the captured Swift error flag and direct
result registers when both layouts are direct. If either the success or concrete
error layout is indirect, the decoder consumes Swift's extra typed-error buffer
after the user arguments and writes failures into that caller-owned storage.
Async dispatch retains that error buffer separately from both the indirect
success result and the saved continuation context. A direct associated error
substitutes its concrete binding and always uses that indirect error buffer;
wrappers containing an associated type remain fail-closed.

Construction rejects architecture-specific unsupported signatures before
allocation. Per-requirement veneers are aligned and packed into page-backed
arenas, with additional pages chained when a graph outgrows one page. Every page
remains writable only while the graph is under construction. The complete arena
is cache-flushed and published read-execute before any registry entry or
existential can expose its veneers. Executable-page publication is checked; a
failed `mprotect` causes construction to fail closed and releases every arena
page. Custom-executor tests cover handler isolation and caller resumption.

See <doc:StubContract> for the authoritative signature and platform boundary.

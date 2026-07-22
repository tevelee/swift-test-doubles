# Architecture

The TestDoubles library implementation remains in one Swift target because its
runtime-generated existentials cross internal metadata, recording, and ABI
boundaries. The source directories are ownership zones, not separate modules.

## Dependency direction

New code should follow this direction:

1. `Metadata` owns neutral protocol, witness, and fabricated-payload
   descriptions. These values must not require concrete runtime-resource or
   recorder types.
2. `Recording` owns matching, behavior selection, invocation history, and
   verification. It may depend on neutral metadata, but retains runtime
   resources only as `AnyObject` ownership.
3. `Runtime` owns unsafe value transport, trampoline dispatch, executable-code
   lifecycle, and the concrete objects hidden behind neutral ownership.
4. `Preparation` coordinates metadata, recording, and runtime to validate and
   fabricate one generated value.
5. Public doubles expose those capabilities without duplicating their internal
   policies.

`CTestDoublesTrampoline` is the machine boundary below Runtime. Its C frame is
the source of truth for shared offsets, and assembly consumes the same header.
Compiler-derived constants must have a fail-closed verification script.

## Runtime ABI planning

Runtime ABI decisions are separated from transport and execution:

- `RuntimeArchitecture`, `RuntimeValueLayout`, and the call-frame planning
  types describe architecture-specific layouts without owning storage.
- `WitnessCallTransportPlan` is the source of truth for the physical locations
  of visible arguments, indirect results, typed-error destinations, dynamic
  Self metadata, and witness tables. Decoding, forwarding, typed adapters, and
  async stack adjustment must consume this plan instead of recreating register
  cursors.
- Dynamic closure support first produces a `FunctionBridgeAnalysis`. Runtime
  execution accepts only a direction-validated `FunctionBridgePlan`, whose
  direct argument transport is nonoptional.

New ABI support should extend these plans first, then add transport at their
named locations. A second manual register allocator is a correctness bug even
when it agrees on the currently tested signatures.

## Runtime ownership

Unsafe value storage uses explicit state rather than paired allocation and
cleanup conventions. `ManagedValueBuffer` distinguishes uninitialized,
borrowed-bit, initialized, and transferred storage, and destroys a value only
while it owns an initialized instance. Callers must mark initialization after
the value witness completes and mark transfer after ABI return bits move to
their final owner.

Pointers retained across C or assembly callbacks pass through
`RetainedRuntimeState`: `retain` creates the callback-owned reference, `borrow`
accesses it while execution is suspended, and `consume` ends that ownership at
the completion callback. Fabricated witness calls resolve their registry
target, recorder, and slot through `ResolvedFabricatedInvocation` before
selecting a synchronous, async, read, or modify dispatch path.

Forwarding keeps three responsibilities separate. `ForwardingTarget` owns the
real existential and linked witness tables, `ProtocolForwardingPlanBuilder`
validates and records immutable ABI entry plans, and the forwarded state types
own suspended call frames and continuations. `ProtocolForwarder` is only the
dispatch facade between those components.

`Scripts/check-internal-boundaries.sh` enforces several narrow ownership rules:

- Runtime cannot extend `Stub.Requirement` or define public `Stub.Invocation`.
- Runtime cannot depend on the generic `Stub` preparation coordinator.
- Metadata and Recording cannot name concrete `StubResources`.
- Neutral `StubPayload`, existential-representation, linked-witness graph, and
  witness-entry layout declarations remain in Metadata rather than Preparation
  or Runtime.

Some model dependencies still span these ownership zones. Metadata uses the
runtime ABI model and symbol lookup, while `MethodDescriptor` refers to the
runtime typed-adapter factory that constructs recording-backed invocations.
Do not extend those cycles. Breaking them or splitting the package target
requires splitting the TestDoubles library target in a separate change with
debug, release, Rosetta, sanitizer, and Xcode-consumer proof.

## Fabricated witness lifetime

`StubResources` builds witness descriptors, tables, invocation registrations,
and executable trampolines as one construction transaction. The transaction
commits only after `FabricatedExistentialStorage` validates and owns the
generated representation.

After commit, descriptor and witness-table addresses remain allocated for the
rest of the process. Swift generic-metadata caches may retain witness identity
without retaining `StubResources`; reusing an address could therefore turn an
old cache key into unrelated descriptor bytes. Invocation registrations,
typed-adapter state, forwarding targets, and executable trampoline pages remain
scoped to the generated payload and are released with it.

If construction throws before commit, no fabricated existential can escape.
The registry and trampoline arena are cleaned up and raw witness allocations
are deallocated instead of entering the process-lifetime arena.

This is intentionally a safety policy rather than a general witness cache.
Reclamation, deduplication, or bounded arenas must not be introduced without a
runtime proof that covers generic specialization and repeated address reuse.

## Executable veneer lifecycle

The C target keeps Swift runtime shims and shared layout assertions in
`TestDoublesTrampoline.c`. Executable-page allocation and arm64/x86_64 veneer
emission live in `WitnessVeneerArena.c`; the assembly entry and resume paths
remain in `TestDoublesTrampoline.S`. Shared async and coroutine descriptor
layouts are declared in the internal `RuntimeDescriptorLayout.h`.

The Swift `TrampolineFactory.Arena` facade has a one-way lifecycle: building,
published or failed, then destroyed. Only building arenas may allocate entries,
publication happens once, and destruction is terminal and idempotent. Invalid
typed-adapter register indexes must be rejected before calling C so a bad
request cannot reserve executable space or poison the arena transaction.

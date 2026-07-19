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

`Scripts/check-internal-boundaries.sh` enforces several narrow ownership rules:

- Runtime cannot extend `Stub.Requirement` or define public `Stub.Invocation`.
- Metadata and Recording cannot name concrete `StubResources`.
- The neutral `StubPayload` declaration remains in Metadata rather than Runtime.

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

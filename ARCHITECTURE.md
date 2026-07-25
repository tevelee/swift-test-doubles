# Architecture

TestDoubles separates its stable test-double semantics from the Swift ABI
machinery used to fabricate protocol conformances. The public product remains
one library, but its implementation has explicit internal target boundaries so
the two areas can change and be validated independently.

## Targets and ownership

```text
TestDoubles (public product)
        │
        ├── TestDoublesRuntime (internal Swift ABI engine)
        │           ├── CTestDoublesTrampoline (C and assembly boundary)
        │           └── Echo (Swift runtime reflection and metadata)
        │
        └── IssueReporting (public diagnostics)
```

`TestDoubles` owns the public API and test semantics:

- `Stub`, `Spy`, `Dummy`, `ManualStub`, builders, matchers, recording,
  verification, and stable `StubError` diagnostics.
- Public requirement and associated-type input values, plus policy such as
  grouped-input diagnostics and capture behavior.
- Semantic endpoint adapters that turn recorder decisions and dummy rejection
  into the runtime's package-scoped dispatch contract.

`TestDoublesRuntime` owns the unsafe and compiler-coupled implementation:

- Protocol and existential metadata inspection, signature discovery,
  associated-type resolution, and ABI shape validation.
- Witness-table and payload fabrication, executable veneer allocation,
  invocation registration, and process-stable witness identity lifetime.
- Argument decoding, result and error encoding, function reabstraction,
  forwarding transport, and synchronous, async, read, and modify dispatch.
- Every Swift-to-C trampoline callback and its retained state.

`CTestDoublesTrampoline` owns only the machine boundary: shared C frame
layouts, executable veneers, assembly entries, and ABI constants. `Echo` owns
generic Swift runtime reflection primitives such as metadata wrappers,
descriptors, witness tables, image inspection, relative pointers, and value
witness operations. TestDoublesRuntime is the only target that imports either
dependency.

`ManualStub` is deliberately outside the generated-runtime path. It is an
ordinary Swift forwarding and recording API and must not import or name the
runtime, Echo, C trampoline, witness-table, or ABI implementation types.

## Runtime dispatch boundary

A generated call follows this path:

```text
protocol call
  → fabricated witness table
  → executable veneer
  → C and assembly trampoline
  → TestDoublesRuntime ABI decode and dispatch
  → TestDoubles semantic endpoint
  → TestDoublesRuntime result/error encode
  → original caller
```

`RuntimeInvocationEndpoint` is the package-scoped seam between the two Swift
targets. The endpoint supplies semantic outcomes such as recording placeholders,
configured values or failures, forwarding, dynamic `Self` payload choices, and
intentional dummy rejection. The runtime owns the raw frame, value ownership,
continuation state, and ABI encoding. It must never name `StubRecorder`,
`StubError`, `Stub`, `Spy`, `Dummy`, or `IssueReporting`.

Runtime argument decoding plans are precomputed per fabricated method in both
borrowed and consuming forms. A normal forwarding call uses the borrowed plan;
a configured override consumes owned values exactly once. Do not reintroduce
per-invocation metadata planning or conflate those ownership paths.

## Fabricated witness lifetime

`FabricatedRuntimeResources` constructs descriptors, witness tables, registry
entries, typed adapters, and executable veneers as one transaction. A generated
existential commits the transaction only after its storage owns the fabricated
payload.

On teardown, invocation registrations are cancelled before the executable
veneer arena is destroyed. Construction failures deallocate unobservable
descriptor and table allocations. Successful identities stay allocated for the
process lifetime because Swift generic-metadata caches can retain witness-table
addresses without retaining the resource owner. Their associated registry,
endpoint, forwarding state, and executable pages remain payload-scoped.

Async, read, and modify callbacks use `RetainedRuntimeState`: retain before
crossing into assembly, borrow while suspended, and consume exactly once in the
completion or resume callback. C callback names and frame layouts are ABI
contracts and must remain unchanged unless the C and assembly layers change in
lockstep.

## Dependency and validation rules

The public target directly depends only on `TestDoublesRuntime` and
IssueReporting. It does not re-export Echo or the C trampoline. Runtime APIs
used across the internal boundary use explicit `package` access; none become
part of the product API by accident.

`Scripts/check-internal-boundaries.sh` enforces the critical source-level
rules: direct low-level imports remain out of the public target, runtime does
not name semantic public types, ManualStub stays source-level, implementation
dependencies are not re-exported, and the key ABI model declarations have one
runtime-owned home.

Runtime or ABI changes require more than a SwiftPM unit pass: run debug and
release tests, formatting and lint, the boundary check, documentation build,
WebAssembly/manual-stub validation where the matching SDK is installed, and
the Xcode consumer validation. Validate new ABI support against every supported
architecture before widening the accepted shape.

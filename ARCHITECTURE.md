# Architecture

TestDoubles separates its stable test-double semantics from the Swift ABI
machinery used to fabricate protocol conformances. The public product remains
one library, but its implementation has explicit internal target boundaries so
the two areas can change and be validated independently.

## Targets and ownership

```text
TestDoubles (public product)
        │
        ├── InternalRuntimeContract (package-only semantic contract)
        │
        ├── TestDoublesRuntimeMetadata (internal metadata engine)
        │           ├── InternalRuntimeContract
        │           ├── TestDoublesRuntimeSupport
        │           ├── CTestDoublesTrampoline (ABI symbol access)
        │           └── Echo (Swift runtime reflection and metadata)
        │
        ├── TestDoublesRuntime (internal execution engine)
        │           ├── InternalRuntimeContract
        │           ├── TestDoublesRuntimeMetadata
        │           ├── TestDoublesRuntimeSupport
        │           ├── CTestDoublesTrampoline (C and assembly boundary)
        │           └── Echo (Swift runtime reflection and metadata)
        │
        ├── TestDoublesRuntimeSupport (shared low-level support)
        │           └── CTestDoublesTrampoline
        │
        └── IssueReporting (public diagnostics)
```

### Direct dependency tree

The diagram above groups the targets by role. This is the actual direct-target
graph, read from the public product toward the machine boundary:

```text
TestDoubles
├── InternalRuntimeContract
├── TestDoublesRuntimeMetadata
│   ├── InternalRuntimeContract
│   ├── TestDoublesRuntimeSupport
│   │   └── CTestDoublesTrampoline
│   ├── CTestDoublesTrampoline
│   └── Echo
├── TestDoublesRuntime
│   ├── InternalRuntimeContract
│   ├── TestDoublesRuntimeMetadata
│   ├── TestDoublesRuntimeSupport
│   ├── CTestDoublesTrampoline
│   └── Echo
└── IssueReporting
```

`TestDoublesRuntimeSupport` is deliberately below both runtime halves. It
prevents symbol lookup, construction errors, and architecture facts from
creating a metadata-to-execution cycle. `Echo` is a package dependency of the
metadata and execution targets, never of the public target or the contract.

### Responsibility map

| Component | Owns | Must not own |
| --- | --- | --- |
| `TestDoubles` | Stable API, recorder, builders, matchers, verification, `StubError`, and semantic endpoints | ABI layouts, witness tables, Echo types, or C frames |
| `InternalRuntimeContract` | Package-only semantic calls, method descriptions, requirement schemas, endpoint outcomes, and typed-adapter token | Runtime descriptors, layouts, symbol lookup, or transport plans |
| `TestDoublesRuntimeSupport` | Construction errors, symbol lookup/cache, and architecture facts | Protocol discovery, fabrication, execution state, or public diagnostics |
| `TestDoublesRuntimeMetadata` | Existential and protocol inspection, layouts, descriptor/schema resolution, and requirement validation | Fabricated invocation registry, endpoint retention, or trampoline execution |
| `TestDoublesRuntime` | Witness fabrication, ABI decode/encode, forwarding, coroutine dispatch, and resource lifetime | Public recorder policy or independent metadata discovery |
| `CTestDoublesTrampoline` | C frame layouts, executable veneers, assembly entries, and ABI constants | Swift semantic dispatch policy |
| `Echo` | Swift runtime reflection primitives used by metadata and prepared-call value operations | Test-double semantics or the public API |

`TestDoubles` owns the public API and test semantics:

- `Stub`, `Spy`, `Dummy`, `ManualStub`, builders, matchers, recording,
  verification, and stable `StubError` diagnostics.
- Public requirement and associated-type input values, plus policy such as
  grouped-input diagnostics and capture behavior.
- Semantic endpoint adapters that turn recorder decisions and dummy rejection
  into the package-scoped runtime contract.
- The local `RuntimeStubFactory` facade. It is the only public-target source
  that imports a runtime target. It turns source-level requirements, effects,
  bindings, and endpoints into an opaque prepared plan with semantic methods,
  then materializes storage without exposing fabricated tables, payloads,
  resource owners, or ABI references.

`InternalRuntimeContract` owns only dependency-free values shared by the two
Swift layers:

- Dense dispatch-slot requests, endpoint outcomes, and the
  `RuntimeInvocationEndpoint` protocol.
- Source-level protocol-shape and associated-type-binding requests.
- Semantic method information: requirement kind and receiver, effects,
  result policy, ownership intent, dynamic-`Self` convention, and dispatch
  identities.
- Explicit requirement schemas and an opaque typed-witness-adapter token.
- An opaque `AnyObject` lifecycle callback that lets the semantic endpoint
  retain published runtime resources without importing their ABI type.

The contract deliberately does not name method descriptors, protocol
descriptors, witness tables, frames, ABI layouts, Echo types, or C types.

`TestDoublesRuntimeSupport` owns low-level facts shared by metadata and
execution: runtime construction errors, process-wide runtime-symbol lookup and
caching, and architecture classification. It must not own protocol discovery,
fabrication, or public semantic policy.

`TestDoublesRuntimeMetadata` owns structural runtime interpretation:

- Protocol and existential metadata inspection, protocol-layout construction,
  signature discovery, associated-type resolution, and explicit-schema
  resolution.
- Requirement descriptors, ABI value classification, type parsing and lookup,
  witness-signature parsing, and thunk discovery.
- Fabricated payload identity and requirement validation. It has no fabricated
  invocation registry, endpoint, forwarding target, or trampoline execution
  state.

`TestDoublesRuntime` owns executable ABI behavior:

- Witness-table and payload fabrication, executable veneer allocation,
  invocation registration, and process-stable witness identity lifetime.
- Argument decoding, result and error encoding, function reabstraction,
  forwarding transport, and synchronous, async, read, and modify dispatch.
- Every Swift-to-C trampoline callback and its retained state, including the
  executable call-frame bridge.
- The execution half of `RuntimeStubFactory`: forwarding transport and the
  full fabrication/lifetime transaction.

The execution target may reflect values while executing a prepared call, but it
consumes the metadata target's descriptors rather than reimplementing
protocol-shape discovery or schema resolution.

`CTestDoublesTrampoline` owns only the machine boundary: shared C frame
layouts, executable veneers, assembly entries, and ABI constants. `Echo` owns
generic Swift runtime reflection primitives such as metadata wrappers,
descriptors, witness tables, image inspection, relative pointers, and value
witness operations. Metadata uses Echo for discovery and structural
interpretation; execution uses it only for prepared-call value operations and
fabricated or forwarded storage. The runtime targets are the only targets that
import Echo; runtime support and the runtime targets may import the C
trampoline target.

`ManualStub` is deliberately outside the generated-runtime path. It is an
ordinary Swift forwarding and recording API and must not import or name the
runtime, Echo, C trampoline, witness-table, or ABI implementation types.

## Example: one generated stub call

For a protocol such as:

```swift
protocol Greeter {
    func greeting(for name: String) -> String
}

let stub = try Stub<any Greeter>()
stub.when { $0.greeting(for: "Ada") }.thenReturn("Hello, Ada")
let greeter = stub()
let value = greeter.greeting(for: "Ada")
```

construction and invocation cross the layers in two distinct phases:

```text
Construction
Stub<any Greeter>
  → RuntimeStubFactory (the sole public-target runtime importer)
  → metadata discovers the protocol shape and requirement signature
  → facade creates an opaque prepared plan
      ├── semantic RuntimeMethod values → StubRecorder
      └── raw descriptors/layout/forwarding transport stay private
  → facade supplies StubRecorderInvocationEndpoint
  → execution fabricates storage, witness table, and executable veneers
  → Storage<any Greeter>.materialize() returns greeter

Invocation
greeter.greeting(for: "Ada")
  → fabricated witness-table entry
  → executable veneer and C/assembly trampoline
  → TestDoublesRuntime decodes ABI arguments into a contract request
  → StubRecorderInvocationEndpoint selects the recorded behavior
  → TestDoublesRuntime encodes "Hello, Ada" for the original caller
```

An unmatched `Spy` call follows the same path through the endpoint, which
returns the contract's forwarding outcome; execution then invokes the retained
target through its prepared forwarding plan. A `Dummy` instead installs a
semantic rejection endpoint, so any requirement call stops with its stable,
source-level diagnostic.

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
targets, declared in `InternalRuntimeContract`. The runtime passes a dense
dispatch slot and boxed values; the semantic endpoint resolves that slot against
its recorder catalog and supplies outcomes such as recording placeholders,
configured values or failures, forwarding, dynamic `Self` payload choices, and
intentional dummy rejection. The runtime retains its method descriptors, raw
frame, value ownership, continuation state, and ABI encoding. It must never
name `StubRecorder`, `StubError`, `Stub`, `Spy`, `Dummy`, or `IssueReporting`.

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

The public target directly depends on `InternalRuntimeContract`, both runtime
targets, and IssueReporting. `InternalRuntimeContract` is dependency-free;
the runtime targets are the only targets that import Echo, while the support
and runtime targets may import the C trampoline. Neither internal dependency
is re-exported. Runtime APIs
used across the internal boundary use explicit `package` access; none become
part of the product API by accident.

`Scripts/check-internal-boundaries.sh` enforces the critical source-level
rules: the contract remains dependency-free, only
`Sources/TestDoubles/Runtime/RuntimeStubFactory.swift` may import a runtime
target, no ABI dependency is re-exported, and ManualStub stays source-level.
Module targets enforce declaration ownership; the script intentionally avoids
fragile semantic-name and declaration-location checks that merely duplicate
those compiler boundaries.

Runtime or ABI changes require more than a SwiftPM unit pass: run debug and
release tests, formatting and lint, the boundary check, documentation build,
WebAssembly/manual-stub validation where the matching SDK is installed, and
the Xcode consumer validation. Validate new ABI support against every supported
architecture before widening the accepted shape.

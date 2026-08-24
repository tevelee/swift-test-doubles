# Architecture

TestDoubles separates its stable test-double semantics from the Swift ABI
machinery used to fabricate protocol conformances. The public product remains
one library. Its implementation uses only the target boundaries that carry a
real dependency constraint; internal directories retain the finer ownership
structure without adding module crossings.

## Targets and ownership

```text
TestDoubles (public product)
        │
        ├── InternalRuntimeContract (package-only semantic contract)
        │
        ├── TestDoublesRuntime (internal execution engine)
        │           ├── InternalRuntimeContract
        │           ├── CTestDoublesTrampoline (C and assembly boundary)
        │           ├── Echo (raw runtime metadata and witness primitives)
        │           ├── EchoRuntimeReflection (semantic function and layout facts)
        │           └── EchoRuntimeSupport (low-level value storage and operations)
        │
        └── IssueReporting (public diagnostics)
```

### Direct dependency tree

The diagram above groups the targets by role. This is the actual direct-target
graph, read from the public product toward the machine boundary:

```text
TestDoubles
├── InternalRuntimeContract
├── TestDoublesRuntime
│   ├── InternalRuntimeContract
│   ├── CTestDoublesTrampoline
│   ├── Echo
│   ├── EchoRuntimeReflection
│   └── EchoRuntimeSupport
└── IssueReporting
```

`TestDoublesRuntime` uses its `Metadata/`, `Support/`, and `Runtime/`
directories for ownership only. They compile together because symbol lookup,
construction errors, architecture facts, metadata discovery, and execution all
serve one ABI implementation and are not independently useful dependencies.
The `Echo` product family is never a dependency of the public target or the
contract.

### Responsibility map

| Component | Owns | Must not own |
| --- | --- | --- |
| `TestDoubles` | Stable API, recorder, builders, matchers, verification, `StubError`, and semantic endpoints | ABI layouts, witness tables, Echo types, or C frames |
| `InternalRuntimeContract` | Package-only semantic calls, method descriptions, requirement schemas, endpoint outcomes, and typed-adapter token | Runtime descriptors, layouts, symbol lookup, or transport plans |
| `TestDoublesRuntime` | Runtime symbol/cache and architecture facts; protocol inspection, layouts, descriptor/schema resolution, fabrication, ABI decode/encode, forwarding, coroutine dispatch, and resource lifetime | Public recorder policy or stable public diagnostics |
| `CTestDoublesTrampoline` | C frame layouts, executable veneers, assembly entries, and ABI constants | Swift semantic dispatch policy |
| `Echo` | Raw Swift runtime metadata, descriptors, containers, witness tables, image inspection, and value-witness primitives | Test-double semantics or the public API |
| `EchoRuntimeReflection` | Stable semantic projections of function effects, parameter facts, and value layouts | Raw metadata pointers, witness tables, or TestDoubles policy |
| `EchoRuntimeSupport` | Low-level temporary value allocation, copy, ownership state, transfer, and destruction | Protocol discovery, ABI classification policy, or recorder semantics |

`TestDoubles` owns the public API and test semantics:

- `Stub`, `Spy`, `Dummy`, `ManualStub`, builders, matchers, recording,
  verification, and stable `StubError` diagnostics.
- Public requirement and associated-type input values, plus policy such as
  grouped-input diagnostics and capture behavior.
- Semantic endpoint adapters that turn recorder decisions and dummy rejection
  into the package-scoped runtime contract.
- The local `RuntimeStubFactory` facade. It is the only public-target source
  that imports a runtime implementation target. It passes source-level
  requirements, effects, bindings, and endpoints to Runtime; Runtime returns
  an opaque prepared plan with semantic methods, which the facade materializes
  without exposing fabricated tables, payloads, resource owners, or ABI
  references.

`InternalRuntimeContract` owns only dependency-free values shared by the two
Swift layers:

- Dense dispatch-slot requests, endpoint outcomes, and the
  `RuntimeInvocationEndpoint` protocol.
- Source-level protocol-shape and associated-type-binding requests.
- Semantic method information: requirement kind and receiver, effects,
  result policy, ownership intent, dynamic-`Self` convention, and dispatch
  identities.
- `RuntimeAssociatedTypeUse`: an ordered summary of the associated-type names
  used by a value. It intentionally omits the surrounding type expression,
  declaration identity, and reference or opaque transport.
- Explicit requirement schemas, grouped preparation inputs, and an opaque
  typed-witness-adapter token/source pair.
- An opaque `AnyObject` lifecycle callback that lets the semantic endpoint
  retain published runtime resources without importing their ABI type.

The contract deliberately does not name method descriptors, protocol
descriptors, witness tables, frames, ABI layouts, Echo types, or C types.
In particular, it does not enumerate supported containers or generic nominal
values:
those are source-schema input on one side of the boundary and the runtime's
validated capability on the other.

`TestDoublesRuntime` is one ABI implementation target, organized internally
as follows:

- `Support/` owns construction errors, process-wide runtime-symbol lookup and
  caching, and architecture classification.
- `Metadata/` owns protocol and existential inspection, protocol-layout
  construction, signature discovery, associated-type and explicit-schema
  resolution, requirement descriptors, type parsing, thunk discovery, and the
  complete `WitnessValueDependency` graph.
- `Runtime/` owns witness-table and payload fabrication, executable veneer
  allocation, invocation registration, process-stable witness identity
  lifetime, argument decoding, result and error encoding, function
  reabstraction, forwarding transport, synchronous/async/read/modify dispatch,
  and every Swift-to-C trampoline callback with its retained state.

`CTestDoublesTrampoline` owns only the machine boundary: shared C frame
layouts, executable veneers, assembly entries, and ABI constants. The `Echo`
product family owns generic Swift runtime facts: raw `Echo` supplies metadata
wrappers, descriptors, witness tables, image inspection, relative pointers,
and value-witness primitives; `EchoRuntimeReflection` supplies stable semantic
function and layout projections; `EchoRuntimeSupport` supplies ownership-aware
temporary value storage plus copy and destruction operations. The runtime uses
raw Echo for discovery and structural interpretation plus semantic projections
where sufficient, and it retains raw Echo only for prepared-call operations
that genuinely require metadata, containers, or witness tables. The runtime
target is the only target that imports an Echo product or the C trampoline
target.

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
  → Runtime resolves the contract request; Metadata discovers the protocol
    shape and requirement signature
  → Runtime returns an opaque prepared plan
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
source-level diagnostic. Concrete `Dummy` values take a separate path through
valid placeholder synthesis; function placeholders point to fail-closed bodies,
while other concrete contents remain unspecified and must not be observed.

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

The public target directly depends on `InternalRuntimeContract`, Runtime,
RuntimeSupport, and IssueReporting. Metadata remains behind Runtime.
`InternalRuntimeContract` is dependency-free; the runtime targets are the only
targets that import an Echo product, while the support and runtime targets may
import the C trampoline. Neither internal dependency is re-exported. Runtime APIs
used across the internal boundary use explicit `package` access; none become
part of the product API by accident.

`Scripts/check-internal-boundaries.sh` enforces the critical source-level
rules: the contract remains dependency-free, only
`Sources/TestDoubles/Runtime/RuntimeStubFactory.swift` may import a runtime
target, no ABI dependency is re-exported, and ManualStub stays source-level.
Module targets enforce declaration ownership; the script intentionally avoids
fragile semantic-name and declaration-location checks that merely duplicate
those compiler boundaries. Its one narrow name check rejects concrete
fabrication types in the public target: that prevents the sole facade from
letting an ABI storage type escape through a semantic API.

Runtime or ABI changes require more than a SwiftPM unit pass: run debug and
release tests, formatting and lint, the boundary check, documentation build,
WebAssembly/manual-stub validation where the matching SDK is installed, and
the Xcode consumer validation. Validate new ABI support against every supported
architecture before widening the accepted shape.

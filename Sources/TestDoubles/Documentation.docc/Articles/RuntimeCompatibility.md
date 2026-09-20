# Runtime Compatibility

Check runtime platform requirements, signature discovery, and supported protocol shapes.

## Overview

Use <doc:ConstructionGuide> to choose a construction route. This article
collects the runtime requirements and limits relevant to that choice.

### Requirements and platforms

TestDoubles requires Swift 6.3. Its declared deployment targets are macOS 13+,
Mac Catalyst 16+, iOS 16+, tvOS 16+, visionOS 1+, and watchOS 9+. CI builds
against those minima and runtime-tests on pinned macOS 26 arm64 and x86_64
hosts, Linux arm64 and x86_64 hosts, and the oldest available arm64 simulator
runtime installed with the pinned Xcode. Android arm64 and x86_64 are
provisional cross-build targets, and wasm32-unknown-wasip1 is a
`ManualStub`-only target.

Android support is cross-build validated in CI for debug and release test
targets with the official Swift 6.3.3 Android SDK and NDK r27d or later. The
dependency graph must resolve Echo 0.1.1 or newer for Android ELF image
discovery. CI also runs a focused x86_64 emulator demonstration that fabricates,
configures, invokes, and verifies a `Stub`. The full test suites do not
currently execute on an Android emulator or device, so Android remains
provisional.

Physical iOS, tvOS, visionOS, and watchOS devices cannot run the executable
runtime trampoline. A generated
[`ManualStub`](ManualStubbing.md)
provides the same `when`/`then`/`verify` API there, and its `automatic()`
factory selects that compiled route without changing call sites.

Generated conformers for protocols inheriting `Actor` are actors themselves;
their `automatic()` factory uses the compiled route so Swift owns the executor
and actor lifetime. `@MainActor` and custom-global-actor protocols can use
runtime stubs and forwarding spies while preserving the protocol's actor hop.

A macOS test process must be allowed to map JIT memory. The runtime allocates
its trampoline pages with `MAP_JIT`, which the kernel rejects with `EINVAL` in
any process signed with the hardened runtime and without the
`com.apple.security.cs.allow-jit` entitlement. Construction then fails closed
with `Could not allocate an executable trampoline for requirement 0`, where the
index only names the first witness slot that was attempted. Command-line
`swift test` binaries are unaffected. Xcode app test targets running on **My
Mac** are affected whenever the host app enables the hardened runtime, because
the `.xctest` bundle is loaded into that host process. Enable the entitlement
on the **host app target**, not on the test bundle:

| Fix | Build setting | Xcode UI |
| --- | --- | --- |
| Allow JIT (recommended) | `RUNTIME_EXCEPTION_ALLOW_JIT = YES` | Signing & Capabilities, Hardened Runtime, "Allow Execution of JIT-compiled Code" |
| Drop the hardened runtime from the test configuration | `ENABLE_HARDENED_RUNTIME = NO` | Build Settings, "Enable Hardened Runtime" |
| Run the tests on a simulator destination | none | pick a simulator instead of My Mac |

```bash
xcodebuild test -scheme YourApp -destination 'platform=macOS' RUNTIME_EXCEPTION_ALLOW_JIT=YES
```

Removing `MAP_JIT` is not a workaround. A plain anonymous mapping can still be
`mprotect`ed to read-execute under the hardened runtime, but executing it
terminates the process with `SIGKILL` under code-signing enforcement, so the
runtime maps `MAP_JIT` and reports the mapping failure instead.

WebAssembly (`wasm32-unknown-wasip1`) has no facility for executable memory
and no register-based calling convention to hand-assemble against, so the
runtime trampoline cannot run there at all, the same limitation as physical
Apple devices, but more fundamental: it isn't a policy restriction to route
around, WASI's own `<sys/mman.h>` rejects even its mmap emulation shim for
executable pages. `Stub`/`Spy` construction fails closed there with the usual
actionable `StubError` diagnostic; use `ManualStub` directly or its generated
`automatic()` factory. CI cross-builds the
library for `wasm32-unknown-wasip1` in debug and release with the official
Swift 6.3.1 WASI SDK, and actually runs both a small standalone executable and
the `TestDoublesWasmTests` suite under `wasmtime`, demonstrating both halves
of that story: `ManualStub` fully configured, invoked, and verified, and
`Stub` construction failing closed. The dependency graph must resolve Echo
0.1.1 or newer, whose C declarations avoid a wasm32 LLVM compiler crash on
unprototyped functions.

### How construction finds your protocol's signatures

`try Stub<any P>()` needs a source for the protocol's requirement signatures:

| Available signature source | Construction |
| --- | --- |
| A concrete conformer is linked into the test process (usually your production implementation) | `try Stub<any P>()`. The conformance is inspected, never invoked. |
| The protocol module is built with library evolution and exports resilient requirement symbols | `try Stub<any P>()`; no conformer needed. |
| Neither | Describe the requirements explicitly with `Stub.Requirement` values; prefer the `signatureOf:` member-reference factories. |

Two cases need a small extra hint:

- **Effectful getters.** Swift's metadata never records whether a getter can
  throw, so a protocol with `get async` or `get throws` properties takes a
  `getterEffects:` list at construction, with one `.throwing` or
  `.nonthrowing` hint per getter. The hints only fix the calling convention;
  `when` still configures values as usual.
- **Class and existential values.** `when` and `verify` closures run once to
  record which requirement they name, and that recording pass needs valid
  temporary values. TestDoubles synthesizes them for most types; for class
  instances and existentials you pass any valid instance via the `using:` and
  `returning:` overloads (for example `Match.any(using: someUser)`). The value is
  used only during recording. It is never matched against or returned.

See the [Construction Guide](ConstructionGuide.md)
for explicit requirement forms, inheritance ordering, and compositions, and
[Getting Started](GettingStarted.md)
for worked examples of both hints.

### How it works under the hood

Construction is a transaction:

1. Requirement signatures are discovered from Swift runtime metadata: a
   linked conformance's records, or resilient per-requirement descriptor
   symbols. Nothing is invoked and no external tool runs.
2. A genuine witness table is fabricated whose entries all land in one fixed
   trampoline, hand-written in assembly for arm64 and x86_64
   (`TestDoublesTrampoline.S`).
3. The trampoline captures the machine state of each call, and the runtime
   reconstructs typed arguments and results exactly per the Swift calling
   convention, including async continuations, error channels, and indirect
   returns.
4. Every reconstructed call flows through the recorder: matcher selection,
   behavior replay, and the invocation log that verification reads.
5. If any step cannot be done exactly, construction throws a `StubError`
   diagnostic and no partially-built value can escape.

Generated values own their runtime resources, so they stay valid even after
the `Stub` itself is released. The details live in
<doc:HowRuntimeStubsWork> and <doc:TrampolineArchitecture>.

### Support matrix and limitations

What's supported:

- Instance and static methods, property getters and setters, subscripts, and
  initializer requirements, in sync, throwing, async, and async-throwing
  forms, including typed `throws` with a concrete or directly bound associated
  error type.
- Protocol inheritance, diamond bases, and multi-protocol compositions;
  class-constrained protocols, and `NSObject`-backed superclass existentials
  on Apple platforms.
- Dynamic `Self` results and automatically discovered direct or single-optional
  `Self` arguments for nonthrowing instance methods. Bound primary associated
  types cover recursive `Optional`, `Array`, `Set`, `Dictionary`, and `Result`
  values, proven linked generic classes, structs, and enums, and the documented
  concrete-reference slice. Native Swift closures work as arguments and results.
- Borrowing property and subscript access through Swift 6.3 `read` accessors
  and Stub-side Swift 6.4 `yielding borrow`, compound assignment and `inout`
  access through `_modify`, concurrent invocation of generated values, behavior
  chains, argument captors, ordered and event-driven verification.
- Requirement-level generic methods, including async and typed-throwing
  stubs, caller-chosen generic results, and forwarding spies for unconstrained
  or `AnyObject`-constrained parameters.
- Explicit compiler-typed adapters for ABI-uncertain imported or resilient
  method and getter results, including async throwing Foundation values.
- Automatic compiler-proven result transport for methods and getters that return
  values from the built-in Foundation placeholder catalog, including `Data`,
  `URL`, `Date`, and `UUID`. Methods, indexed getters, forwarding spies,
  supported closure results, and tuple leaves may reuse those proofs. Tuples
  may be nested and mix direct with caller-owned indirect members. Swift 6.3
  includes direct-transport entries such as `Data`; indirect entries require
  Swift 6.4 or newer.

Key limitations:

- Unbound associated types beyond the documented caller-bound slice are
  rejected. `Self` arguments remain unsupported in explicit schemas, Spies,
  superclass-constrained existentials, throwing methods, `inout`, and wider or
  nested wrappers.
- Async Stub requirements may fill the argument-register banks and use the
  documented complete integer, floating-point, SIMD, indirect, and
  platform-correct narrow stack shapes. Async Spy forwarding retains up to
  eight visible stack words; dynamic closure bridging has a separate one-word
  stack boundary.
- Typed-throwing getters require explicit `signatureOf:` requirements and are
  not forwarded by Spy. Objective-C-only protocols and native-Swift-only
  superclass constraints are outside the boundary.
- Protocols that relax `Copyable` or `Escapable` are rejected because recorder
  values are retained as escaping `Any` payloads.
- Physical device targets don't run the executable trampoline; use
  `ManualStub` there.
- A macOS test host signed with the hardened runtime cannot map the
  trampoline's JIT pages until the host app carries the
  `com.apple.security.cs.allow-jit` entitlement
  (`RUNTIME_EXCEPTION_ALLOW_JIT = YES`).

Everything above fails closed: an unsupported shape throws an actionable
`StubError` at construction. The precise, normative contract is in the
[Stub Contract](StubContract.md),
with deep dives in
[Function Values](FunctionValues.md)
and
[Bound Associated Types](BoundAssociatedTypes.md).

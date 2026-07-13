# Trampoline Architecture

How RuntimeStub turns an ordinary protocol witness call into one metadata-driven
Swift dispatch path.

## Overview

RuntimeStub does not compile a Swift implementation for every protocol method.
It installs a tiny executable veneer in each mockable witness-table slot. Every
synchronous veneer branches to one architecture entry point and every
asynchronous veneer branches to a second entry point:

```text
protocol existential call
        |
        v
patched or fabricated witness-table slot
        |
        v
per-slot veneer: embed (slot, witness-table context)
        |
        +---- synchronous ----> td_swift_trampoline_entry
        |                              |
        |                              v
        |                  td_swift_trampoline_handler
        |                              |
        |                  decode -> dispatch -> encode -> return
        |
        +---- asynchronous ----> td_swift_async_trampoline_entry
                                       |
                                       v
                         td_swift_async_trampoline_handler
                                       |
                         decode -> select configured behavior
                              /                     \
                 immediate encode            retained async state
                         |                          |
                  resume caller        td_swift_async_dispatch
                                                    |
                                      await on the caller's task
                                                    |
                              td_swift_async_trampoline_complete
                                                    |
                                              resume caller
```

The veneers identify a requirement and a particular stub. The assembly entry
points only capture and restore ABI state. `TrampolineHandler.swift` owns type
resolution, value-witness operations, recorder dispatch, errors, and return
encoding. This separation keeps protocol setup, machine code, ABI
classification, and test behavior in different components.

The stable Swift breakpoints for intercepted calls are:

```text
td_swift_trampoline_handler
td_swift_async_trampoline_handler
```

The second endpoint either completes an async call immediately or prepares the
same-task suspending bridge.

## Source Map

| Layer | File | Main responsibility |
|---|---|---|
| Public proxy | `RuntimeStub.swift` | Own resources and build the protocol existential returned by `stub()` |
| Protocol setup | `RuntimeStubPreparation.swift` | Discover or fabricate a witness table, install veneers, and register descriptors |
| Signature sources | `SignatureDiscovery.swift`, `ModuleSignatureDiscovery.swift`, `Slot.swift` | Describe slot order, effects, argument types, and return types |
| ABI classification | `RuntimeABI.swift` | Map resolved Swift types to GP, FP, aggregate, or indirect ABI storage |
| Veneer API | `TrampolineFactory.swift` | Select synchronous or asynchronous C veneer allocation |
| Executable veneers | `CTestDoublesTrampoline/TestDoublesTrampoline.c` | Allocate an executable page and emit slot/context branch code |
| Capture/restore | `CTestDoublesTrampoline/TestDoublesTrampoline.S` | Spill incoming state, call Swift, restore outgoing state, and return or resume |
| Shared frame contract | `CTestDoublesTrampoline/include/TestDoublesTrampoline.h` | Define `TDCallFrame`, offsets, and exported C entry points |
| Swift endpoint | `TrampolineHandler.swift` | Decode arguments, dispatch the recorder, encode returns, and create Swift errors |
| Stub behavior | `StubRecorder.swift` | Match configured behavior, record calls, and support recording/verification modes |
| Context lookup | `MockRegistry.swift` | Resolve the witness-table context to the owning recorder |
| ABI tests | `RuntimeABITests.swift` | Exercise register, stack, aggregate, indirect, throwing, async, and concurrency paths |

## Setup Paths

RuntimeStub has three signature sources, but all three converge on the same
trampoline installation and handler.

### Clone an Existing Witness Table

`RuntimeStub<any P>()` calls `prepare()`:

1. Echo extracts the protocol descriptor for `P`.
2. Echo finds an existing conformance and its witness-table pattern.
3. `SignatureDiscovery` reads each witness function symbol with `dladdr`,
   demangles it, and parses the requirement signature.
4. RuntimeStub allocates and copies `1 + protocol.numRequirements` pointer
   words.
5. `patchWitnessTable` replaces each mockable requirement entry with a veneer.
6. The cloned witness-table pointer becomes the registry context key.
7. RuntimeStub builds an existential using the real conformer's type metadata
   and the cloned table.

This is the shortest test-author API, but discovery still depends on a real
conformer and sufficiently useful symbols. The final marshalling is
metadata-driven; zero-config signature discovery itself still starts with
demangled text.

### Fabricate a Witness Table

Explicit ``Slot``/``MethodDescriptor`` setup and
``RuntimeStub/makeFromModule(moduleName:)`` call `prepareFabricated`:

1. RuntimeStub reads the protocol descriptor directly from `P`.
2. Explicit slots provide concrete `Any.Type` names, or module discovery uses
   `swift symbolgraph-extract` to obtain structured signatures.
3. `fabricateWitnessTable` allocates a compact conformance descriptor, nearby
   indirect protocol/type cells, and an absolute witness table in one block.
4. The payload metadata is the library-owned `RuntimeStubPayload` class.
5. Every described requirement receives a veneer and a
   `RuntimeMethodDescriptor`.
6. `callAsFunction()` injects the retained payload pointer into a copied
   existential container before returning `P`.

This path needs no real conformer. The fabricated conformance exists to build
this existential directly; it is not registered as a general runtime
conformance. An unrelated value therefore must not be expected to succeed at
`as? P` because this stub exists.

### Skipped Requirement Records

Preparation excludes records that are not ordinary callable method entries:

- base-protocol records
- associated-type access functions
- associated-conformance access functions
- `_read` coroutine accessors
- `_modify` coroutine accessors

Explicit slot order means protocol requirement order after those records are
removed. Explicit `MethodDescriptor` indexes are raw protocol requirement
indexes and are validated for range and duplicates.

## Per-Slot Veneers

There is one small veneer per installed requirement, not one full marshalling
thunk per signature. A veneer embeds two constants:

- `slot`: the requirement index used to find `RuntimeMethodDescriptor`
- `context`: the cloned or fabricated witness-table address used to find the
  owning `StubRecorder`

`td_make_witness_trampoline` allocates a VM page as read/write, emits a few
instructions, flushes the instruction cache, and changes the page to
read/execute. The emitted code loads slot and context into reserved scratch
registers and branches to `td_swift_trampoline_entry`. The x86_64 veneer uses
a RIP-relative indirect jump so it does not overwrite the incoming indirect
result pointer in `rax`.

| Architecture | Slot | Context | Branch scratch |
|---|---:|---:|---:|
| arm64 | `x16` | `x15` | `x17` |
| x86_64 | `r11` | `r10` | none; RIP-relative indirect jump |

An async witness entry points to a compact `TDAsyncFunctionPointer` descriptor,
not directly to the emitted instructions. The descriptor stores a relative
offset to code at byte 16 and an expected async-context size of 32 bytes. The
code then loads the same slot/context pair and branches to
`td_swift_async_trampoline_entry`.

The current allocator consumes one full VM page per requirement even though a
veneer is only a few instructions. This keeps ownership and `munmap` simple,
but memory use scales with protocol requirement count. Page pooling is a
possible optimization; it would need synchronized allocation and page-level
write/execute transitions.

## The Call Frame

Assembly and Swift exchange state through the 512-byte `TDCallFrame`. The C
header is the source of truth for both the struct and assembly offsets. C
`_Static_assert`s fail the build if the compiler's layout stops matching those
constants.

| Offset | Size | Field | Meaning |
|---:|---:|---|---|
| 0 | 8 | `slot` | Protocol requirement index embedded by the veneer |
| 8 | 8 | `context` | Witness-table registry key embedded by the veneer |
| 16 | 128 | `gp[16]` | Captured general-purpose register words |
| 144 | 256 | `fp[16]` | Captured 128-bit vector registers; Swift currently reads each low word |
| 400 | 8 | `stackPointer` | Pointer to the caller's first stack argument |
| 408 | 8 | `indirectResult` | Caller-provided result storage when the convention exposes it |
| 416 | 8 | `swiftSelf` | Captured Swift self register |
| 424 | 8 | `swiftError` | Captured synchronous Swift error register |
| 432 | 8 | `reserved` | Async context for the asynchronous entry path |
| 440 | 32 | `returnGP[4]` | General-purpose return or continuation values |
| 472 | 32 | `returnFP[4]` | Floating-point return or continuation values |
| 504 | 8 | `returnError` | Outgoing synchronous or asynchronous error object |

Stack arguments are not copied into a fixed buffer. Assembly captures the
caller's stack-argument pointer, and the Swift handler reads successive
eight-byte words while the intercepted call is still active. This avoids an
arity cap and a guessed maximum stack-copy size. Argument decoding therefore
finishes synchronously before a suspending handler starts; the owned `[Any]`
values may cross suspension, but the original stack pointer is never read
after the entry frame is released.

## Synchronous Entry

`td_swift_trampoline_entry` performs the same phases on both architectures:

1. Establish a normal stack frame and reserve 512 bytes.
2. Save the veneer slot and context.
3. Spill GP and vector registers.
4. Record the original stack-argument pointer and Swift special registers.
5. Call `td_swift_trampoline_handler(&frame)` with the platform C convention.
6. Load GP, FP, and error results from the frame.
7. Restore Swift self, release the frame, and return to the protocol caller.

The special-register mapping is:

| State | arm64 | x86_64 |
|---|---:|---:|
| Indirect result | `x8` | `rax` |
| Swift self | `x20` | `r13` |
| Swift error | `x21` | `r12` |
| C handler argument | `x0` | `rdi` |

The handler can write up to four GP and four FP return values. The assembly
restores them into the registers used by the covered direct-return shapes. On
arm64 and x86_64, indirect results are initialized in the caller-owned address
captured from `x8` or `rax`, respectively. The x86_64 return path also restores
that address to `rax`. The ABI suite validates the arm64 path natively and the
x86_64 path under Rosetta on Apple Silicon.

## Asynchronous Entry

Swift async calls do not return to the original link register in the ordinary
way. `td_swift_async_trampoline_entry` captures the call and asks
`td_swift_async_trampoline_handler` whether the selected behavior is immediate
or suspending.

| State | arm64 | x86_64 |
|---|---:|---:|
| Async context | `x22` | `r14` |
| Resume function | `[x22 + 8]` | `[r14 + 8]` |
| Indirect result used by current path | `x0` | `rdi` |
| Error continuation value | `x20` | `r13` |

`returns`, synchronous `then` closures, recording, and verification use the
immediate path. After Swift encodes the response, assembly loads continuation
GP/FP values, loads `returnError`, restores the async context, and branches
directly to its resume function.

Async `then` closures and the equivalent `thenAsync` spelling use a second path
that remains inside the caller's structured task:

1. The synchronous preparation endpoint resolves the recorder, decodes all
   arguments into owned `[Any]` values, selects the best matching async handler,
   records the call, and retains an invocation state containing a copied frame.
2. Assembly reads the compiler-emitted `td_swift_async_dispatchTu` descriptor,
   allocates its required context with `swift_task_alloc`, and links that child
   context to the original caller context.
3. Assembly installs `td_swift_async_trampoline_complete` as the child
   continuation, puts the retained state in the first argument register, makes
   the child the current async context, and tail-branches to
   `td_swift_async_dispatch`.
4. The Swift async dispatch function awaits the configured handler. Success or
   failure is encoded into the state-owned frame.
5. The completion functlet deallocates the child task frame, consumes the
   retained state, restores continuation return values, and branches to the
   original caller continuation.

The emitted witness descriptor reserves 32 bytes in the caller context:

| Offset | Meaning |
|---:|---|
| 0 | Parent async context managed by the caller/compiler |
| 8 | Caller resume function |
| 16 | Child dispatch context allocated for a suspending handler |
| 24 | Retained `AsyncDispatchState` pointer |

Because the bridge calls a Swift async function on the existing task instead
of creating an unstructured `Task`, task-local values, priority, cancellation,
and actor executor semantics flow into the handler.

Both immediate and suspending behavior use the same public setup vocabulary:

```swift
let stub = RuntimeStub<any AsyncStore>()

await stub.when { try await $0.load(id: any()) }.returns(Item.fixture)
await stub.when { try await $0.remove(id: any()) }
await stub.when { try await $0.load(id: equal(42)) }.then { (id: Int) in
    try await fixtureStore.load(id: id)
}

let store: any AsyncStore = stub()
let item = try await store.load(id: 42)

await stub.verify { try await $0.load(id: equal(42)) }.wasCalled()
```

## Swift Handlers

The synchronous and async-preparation endpoints are deliberately tiny:

```swift
@_cdecl("td_swift_trampoline_handler")
func td_swift_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
)

@_cdecl("td_swift_async_trampoline_handler")
func td_swift_async_trampoline_handler(
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
) -> UnsafeMutableRawPointer?
```

They unwrap the frame and forward to `RuntimeTrampolineHandler`. The shared
preparation work then:

1. Reads `slot` and `context`.
2. Resolves `context` through `MockRegistry`.
3. Looks up the slot's `RuntimeMethodDescriptor` in `StubRecorder`.
4. Decodes ABI state into `[Any]` values.
5. Dispatches immediate configured behavior or prepares a retained async state.
6. Encodes an ABI-valid return, recording placeholder, or Swift error.

The suspending path adds one compiler-native Swift async entry point and one
C-callable completion bridge:

```swift
@_silgen_name("td_swift_async_dispatch")
func td_swift_async_dispatch(_ rawState: UnsafeMutableRawPointer) async

@_cdecl("td_swift_async_dispatch_finish")
func td_swift_async_dispatch_finish(
    _ rawState: UnsafeMutableRawPointer?,
    _ rawFrame: UnsafeMutablePointer<TDCallFrame>?
)
```

Keeping the exported function C-callable gives assembly one stable symbol even
when private Swift symbol mangling changes.

## Type Resolution

`RuntimeMethodDescriptor` resolves each qualified argument and return name once
when the witness table is prepared. Resolution tries:

1. Explicit built-in mappings such as `Swift.Int`, `Swift.String`, and
   `Swift.Double`.
2. Swift's `_typeByName` with the qualified name.
3. A `Swift.` prefix for unqualified standard-library names.
4. Nominal struct, enum, and class manglings for `Module.Type` names.
5. `swift_getTypeByMangledNameInContext` for an available mangled type name.

Explicit slots are the most reliable metadata source because they begin with
real `Any.Type` values and store `String(reflecting:)` names. Module discovery
provides qualified structured names. Zero-config discovery parses witness
symbols and can fail for stripped symbols or signatures outside its parser.

When type lookup fails, a small legacy fallback vocabulary (`W1`, `W2`, `FX`,
and `INDIRECT`) can classify simple shapes, but it cannot provide value-witness
ownership for arbitrary custom values. Prefer explicit slots over fallback
tokens for custom types.

## ABI Classification

`abiClass(for:fallbackName:isReturn:)` uses real metadata and its value witness
table to classify a value:

- size zero: `void`
- `Float` or `Double`: one FP value
- one to eight bytes: one GP word
- nine to sixteen bytes: two GP words
- supported mixed struct argument up to sixteen bytes: decomposed GP/FP parts
- supported direct struct return: up to four decomposed GP/FP parts
- larger or unsupported value return: caller-owned indirect storage
- larger argument: pointer to indirect argument storage

Direct aggregate decomposition recursively follows Echo struct field metadata
and field offsets. Current leaf support includes integer-like scalars,
`Float`, `Double`, `String`, and class references. A direct return is accepted
only when decomposition produces at most four total parts, four GP parts, and
four FP parts.

This classifier is intentionally narrower than the complete Swift ABI. A type
being reflectable does not prove that every generic, resilient, ownership, or
lowered calling-convention detail is covered.

## Argument Decoding

The handler maintains independent GP and FP cursors plus a shared stack-word
cursor. The register limits used for ordinary arguments are:

| Architecture | GP argument registers | FP argument registers |
|---|---:|---:|
| arm64 | 8 | 8 |
| x86_64 | 6 | 8 |

For each signature argument:

- `floatingPoint` reads the next FP register or stack word and boxes the bits as
  `Float` or `Double`.
- `integer(words:)` reads one or two GP words into aligned scratch storage and
  boxes the declared type.
- `aggregate` reconstructs a zeroed temporary value from the classified GP/FP
  field parts, then boxes it.
- `indirect` reads an argument address and copies the pointee into an `Any`.

`boxValue` opens the resolved runtime metatype and performs a typed Swift load
into `Any`. This lets the compiler apply the correct copy and reabstraction
rules at the ownership boundary, so captured arguments become proper owned
Swift values. References and reference-containing structs do not depend on a
return-type string heuristic or a global keep-alive buffer.

For an async indirect return, the current continuation convention consumes the
first GP position for result storage, so ordinary argument decoding starts at
GP index one.

## Return Encoding

Before writing a response, `encodeReturn` zeroes all GP and FP return slots.
It then follows the return classification:

- `void`: leave return storage zeroed.
- `floatingPoint`: copy the typed value and place its low word in `returnFP[0]`.
- `integer(words:)`: copy one or two words into `returnGP`.
- `aggregate`: copy the typed value, read its classified field parts, and place
  each part in the next GP or FP return slot.
- `indirect`: use the declared metadata's `initializeWithCopy` to initialize the
  caller-provided result buffer.

The result's dynamic type is checked against the descriptor's expected
metadata before copying. A mismatched `.returns(...)` value fails at the
trampoline boundary instead of returning unrelated bits.

Temporary return storage is copied with the value witness table and then
deallocated without destruction because ownership of that initialized copy is
transferred through the ABI return registers or indirect result buffer.

## Throwing Calls

Throwing dispatch has separate success and failure paths:

- Success clears `returnError` and encodes the normal result.
- Failure reflects the dynamic error value, finds its `Error` conformance,
  calls the C bridge to `swift_allocError`, and initializes the allocated error
  payload with `initializeWithCopy`.

Synchronous assembly restores that object through the Swift error register
(`x21` or `r12`). Async assembly sends it through the continuation error value
(`x20` or `r13`). This is why a stock C calling-convention adapter is not enough
for this design: Swift self, Swift error, indirect results, and async context
are part of the contract.

## Recording Placeholders

`when` and `verify` discover a method by actually invoking the protocol proxy
while `StubRecorder.mode` is `.recording` or `.verifying`. The Swift caller must
still receive a valid value even though that value is discarded.

`encodeRecordingPlaceholder` supplies one:

- numeric values, booleans, and floating-point values use zero
- `String` uses an initialized empty string
- selected arrays use initialized empty storage
- supported structs are recursively initialized field by field
- direct aggregate placeholders are split into return registers
- indirect placeholders are initialized in caller-owned result storage

If RuntimeStub cannot prove that it can initialize every field, it fails with a
message directing the test to CompiledStub or ManualStub. Blindly zeroing an
arbitrary value would violate ownership for strings, arrays, references, and
other nontrivial types.

Recording mode belongs to the whole recorder. Configure and verify one stub
serially. After configuration, normal dispatch and call-log storage are
lock-protected and may be invoked concurrently; configured handler closures
remain responsible for their own captured mutable state.

## Ownership and Lifetime

`RuntimeStubResources` owns the complete runtime installation:

- the cloned witness table or combined fabricated allocation
- the registry key
- every executable veneer page

It registers the recorder only after all method entries are installed. On
deinitialization it removes the registry entry, unmaps every veneer with
`td_free_witness_trampoline`, and deallocates the witness/conformance storage.
The `RuntimeStub` keeps these resources and the fabricated payload alive for as
long as any proxy should be used.

Do not retain a proxy past the lifetime of its owning `RuntimeStub`. Its witness
table and executable veneers are owned by that stub.

Each suspending invocation separately retains an `AsyncDispatchState`. The
completion functlet consumes that retain after the Swift async handler returns.
If a handler remains suspended, its invocation state intentionally remains
alive with the caller task.

## Debugging

Set these symbolic breakpoints to inspect synchronous and asynchronous
RuntimeStub calls:

```text
(lldb) breakpoint set --name td_swift_trampoline_handler
(lldb) breakpoint set --name td_swift_async_trampoline_handler
```

At function entry, the frame pointer is the first C argument (`x0` on arm64,
`rdi` on x86_64). The frame-offset table above lets you inspect raw capture
state directly:

```text
# arm64, stopped at the exported handler entry
(lldb) register read x0
(lldb) memory read --format x --size 8 --count 64 $x0

# x86_64
(lldb) register read rdi
(lldb) memory read --format x --size 8 --count 64 $rdi
```

For typed values, step into `RuntimeTrampolineHandler.handle` or
`prepareAsync` and stop after `decodeArguments`. Inspect `slot`, `method.name`,
`method.qualifiedArgs`, `method.qualifiedRet`, and `args`. Stop after
`encodeReturn` to inspect `returnGP`, `returnFP`, `indirectResult`, and
`returnError`.

Use lower-level breakpoints when the frame itself looks wrong:

```text
(lldb) breakpoint set --name td_swift_trampoline_entry
(lldb) breakpoint set --name td_swift_async_trampoline_entry
(lldb) breakpoint set --name td_swift_async_dispatch
(lldb) breakpoint set --name td_swift_async_trampoline_complete
```

The per-slot veneers have no stable symbol because they are emitted into
anonymous executable pages. Break on the shared assembly entry instead and
inspect the slot/context scratch registers before the first stores.

Typical failure locations:

| Symptom | Inspect first |
|---|---|
| Wrong method receives call | `frame.slot`, explicit descriptor indexes, skipped requirement records |
| Recorder cannot be resolved | `frame.context`, `MockRegistry`, stub lifetime |
| Arguments shift after a threshold | GP/FP cursor counts and `stackPointer` |
| Custom value becomes invalid | resolved `Any.Type`, VWT size/alignment, aggregate classification |
| Large return traps | `indirectResult` and return ABI classification |
| Throwing call returns garbage | `isThrowing`, `returnError`, Swift error allocation |
| Async call never resumes | async descriptor, child context, completion functlet, resume function at context offset 8 |
| `when` crashes before `.returns` | recording-placeholder support for the return type |

## Current Coverage and Limits

The ABI suite currently exercises:

- mixed `Float` and `Double` arguments
- GP and FP register exhaustion into stack arguments
- custom value and class-reference arguments
- mixed GP/FP aggregate arguments
- synchronous throwing success and failure
- mixed direct aggregate returns
- large indirect struct returns
- explicit metadata without a real conformer
- async integer, floating-point, direct aggregate, and indirect returns
- suspending async success, failure, and void handlers
- typed suspending handlers with zero through six arguments
- unified specificity selection across `returns`, immediate `then`, async
  `then`, and `thenAsync` registrations
- enum, optional, mixed tuple, concrete metatype, and opaque existential
  arguments and returns through immediate and suspending async handlers
- recording and verification placeholders for those focused extended ABI shapes
- concrete type metadata preservation for type-based and method-reference slots
- early, actionable rejection of closure requirements that need compiler-generated
  witness reabstraction
- task-local, MainActor, and cancellation propagation through suspension
- concurrent suspending async calls and call recording

The six-integer-argument async invocation is currently exercised on arm64 only.
On x86_64 it crosses an unhandled continuation-register boundary; the typed
six-argument handler still receives compile-time coverage there.

Important unsupported or not-yet-proven areas include:

- `_read` and `_modify` coroutine accessors
- associated-type and associated-conformance witness accessors
- generic requirements whose concrete metadata depends on invocation context
- `inout`, ownership-qualified, move-only, or noncopyable values
- closure arguments and returns, which RuntimeStub rejects because protocol
  witnesses require compiler-generated function reabstraction thunks
- tuple, enum, optional, existential, and metatype layouts beyond the focused
  cases above, including class-constrained/composed existentials and existential
  metatypes
- resilient aggregate lowering not represented in `RuntimeABI`
- custom-executor async edge cases beyond the tested MainActor path
- zero-config discovery from stripped or relative/generic witness-table forms
- executable-memory environments that reject runtime `mmap` plus `mprotect`
- native execution coverage on every supported architecture and OS combination

Treat a new type shape as supported only after adding a focused
`RuntimeABITests` case that passes through an actual protocol existential. A
successful metadata lookup alone is not an ABI conformance test.

## Maintenance Checklist

When changing the trampoline:

1. Keep frame constants and `TDCallFrame` in
   `TestDoublesTrampoline.h` as the shared layout definition.
2. Update C static assertions, arm64 assembly, x86_64 assembly, and Swift frame
   accessors together.
3. Preserve the veneer scratch-register contract on both architectures.
4. Add a protocol-level test for each new argument, return, throw, or async
   shape.
5. Run the ABI suite natively where possible and at least cross-build the other
   architecture. On Apple Silicon, use Swift Testing without XCTest to execute
   the x86_64 build under Rosetta.
6. Verify recording mode as well as normal dispatch; placeholders exercise a
   separate return path.
7. Verify both success and failure for throwing changes.
8. Verify async continuation return and error paths separately from sync
   return-register paths.
9. For suspending changes, verify task-local state, actor execution,
   cancellation, concurrent calls, and invocation-state lifetime.
10. Run `git diff --check` and build the DocC catalog so offset tables and source
   links do not drift unnoticed.

The design goal is not to teach Swift how to call arbitrary bytes. It is to
capture one known witness invocation, recover its declared types, and let real
Swift metadata perform every ownership-sensitive copy.

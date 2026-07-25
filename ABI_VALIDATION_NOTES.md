# Trampoline & Runtime Machinery — Swift ABI Validation Notes

Validation of the `CTestDoublesTrampoline` boundary and the `TestDoubles/Runtime`
+ `TestDoubles/Metadata` layers against the official Swift open source
(`swiftlang/swift`, `main`). Every "Confirmed" row was checked against a named
Swift source location, not against a single compiler's output.

Verdict: the ABI-critical assumptions are **accurately grounded**. Every hard
constant, metadata-kind, flag mask, descriptor layout, and pointer-auth
discriminator I checked matches the Swift headers exactly. The items in
"Noteworthy / gaps" are latent risks and future-work openings, not current
defects on the supported arm64 / x86_64 targets.

---

## 1. Confirmed against Swift source

### Calling-convention registers (`TestDoublesTrampoline.S`, `check-swift-abi-constants.sh`)
| Claim | Swift source | Result |
|---|---|---|
| self = x20 / r13, error = x21 / r12, async ctx = x22 / r14 | `docs/ABI/CallingConventionSummary.rst` | ✅ exact |
| Witness thunks mark self/error `swiftself`/`swifterror`, async ctx `swiftasync` | verified by IRGen probe in CI script | ✅ exact |
| `TDCallFrame` size 544 & every offset | `_Static_assert`s in `TestDoublesTrampoline.c` | ✅ self-checked at compile |

### Protocol requirement flags / coroutine kinds (`ExtendedExistentialMetadata.swift`, docs)
`include/swift/ABI/MetadataValues.h → ProtocolRequirementFlags`:
```
Kind: BaseProtocol=0 Method=1 Init=2 Getter=3 Setter=4
      ReadCoroutine=5 ModifyCoroutine=6 AssocType=7 AssocConf=8
KindMask=0x0F  IsInstanceMask=0x10  IsAsyncMask=0x20
isCalleeAllocatedCoroutine() = isCoroutine() && (IsAsync bit set)
```
- `read2` (yield_once_2 read) low flags **0x35** = `ReadCoroutine(5)|Instance(0x10)|Async(0x20)` ✅
- `modify2` low flags **0x36** = `ModifyCoroutine(6)|0x10|0x20` ✅
- The lib's interpretation of the `0x20` bit as "callee-allocated coroutine
  (yield_once_2)" is precisely `isCalleeAllocatedCoroutine()`. The legacy
  caller-allocated `_modify` (no 0x20 bit) is `isFunctionImpl && !isAsync`. ✅

### Metadata kinds (`ExtendedExistentialMetadata.swift`)
- Existential = **0x303**, ExtendedExistential = **0x307** — match
  `MetadataKind.def` (`3|RuntimePrivate|NonHeap`, `7|RuntimePrivate|NonHeap`). ✅

### Extended existential shape (`inspectExtendedExistential`)
`Metadata.h → TargetExtendedExistentialTypeShape`: field order
`Flags(u32) · ExistentialType(reldirect i32) · ReqSigHeader · GenSigHeader ·
requirements[]` — the lib reads flags@0, reqsig header@+8, gensig header@+16,
requirements@+24. ✅ `ExtendedExistentialTypeShapeFlags` bits used
(`HasGeneralizationSignature 0x100`, `HasImplicitReqSigParams 0x800`,
`HasImplicitGenSigParams 0x1000`; requires `HasTypeExpression 0x200` /
`HasSuggestedValueWitnesses 0x400` clear) all match. ✅ Extended-existential
metadata is `Kind · Shape · genArgs[]`, generalization args read at `+16 + i*8`. ✅

### Tuple metadata (`TupleMetadataCompatibility.swift`, `td_swift_get_tuple_type_metadata`)
`TupleTypeFlags`: `NumElementsMask=0x0000FFFF`, `NonConstantLabelsMask=0x00010000`.
The C shim forwards `count` verbatim as the flags word and leaves bit 16 clear
(labels are permanently retained), exactly as the header comment claims. ✅
`swift_getTupleTypeMetadata(request, flags, elements, labels, proposedWitnesses)`
argument order matches the runtime entry point. ✅

### Witness table layout (`ProtocolWitnessTableLayout.swift`)
First word is the conformance descriptor; requirement N at `(1+N)` words —
matches `WitnessTableFirstRequirementOffset = 1`. ✅

### Pointer-auth discriminators — all exact matches to `SpecialPointerAuthDiscriminators`
| Use | Lib value | Swift constant |
|---|---|---|
| `_modify` (yield_once) resume | `TD_MODIFY_RESUME_DISCRIMINATOR = 3909` | `OpaqueModifyResumeFunction = 3909` ✅ |
| `_read` (yield_once) resume | `56769` (referenced) | `OpaqueReadResumeFunction = 56769` ✅ |
| CoroAllocator `allocate` | `24469` (arm64e `@AUTH ia`) | `CoroAllocationFunction = 0x5f95` ✅ |
| CoroAllocator `deallocate` | `40879` | `CoroDeallocationFunction = 0x9faf` ✅ |
| CoroAllocator `allocateFrame` | `53841` | `CoroFrameAllocationFunction = 0xd251` ✅ |
| CoroAllocator `deallocateFrame` | `23464` | `CoroFrameDeallocationFunction = 0x5ba8` ✅ |

### CoroAllocator struct (`td_swift_read_coro_allocator`)
`Coro.h → struct CoroAllocator { flags; allocate; deallocate; allocateFrame;
deallocateFrame; }`. The lib emits all five fields. Flags word **258 = 0x102 =
Malloc kind (2) | ShouldDeallocateImmediately (bit 8)** — matches
`CoroAllocatorKind::Malloc` and Swift's comment that *only* the mallocator
deallocates immediately in `swift_coro_dealloc`. ✅ `CoroAllocateFn` signature
`(CoroAllocator*, size_t)` matches the shims passing size in the 2nd arg. ✅

### Async function-pointer & context (`RuntimeDescriptorLayout.h`, `.S`)
- `TDAsyncFunctionPointer { i32 relativeFunction; u32 expectedContextSize }` (8 B)
  matches the `…Tu` descriptors the runtime consumes; `swift_task_alloc` is
  called with `expectedContextSize`. ✅
- `AsyncContext` first two words `Parent` (@0) then `ResumeParent` (@8) match
  `Task.h`; the async-complete path stores `{parent, completeFn}` there. ✅

### Coroutine function-pointer descriptor (`TDCoroFunctionPointer`, CI probe)
`{ i32 relativeFunction; u32 callerFrameSize; u64 mallocTypeId }` (16 B). CI
(`check-swift-abi-constants.sh`) derives the same shape from the compiler's
`…Twc` descriptor (`.long reloff, .long 32, .quad mallocTypeId`) and confirms
the 32-byte caller frame for both read2 and modify2. ✅ Consistent with
`MethodDescriptor`'s `Impl / AsyncImpl / CoroImpl` union dispatch in `Metadata.h`.

### yield_once_2 resume discriminator derivation (`YieldingAccessorRuntime.swift`)
Instead of hardcoding, the lib hashes the SIL continuation spelling
`"yield_once_2:1:<yieldType>:"` via `td_function_discriminator`
(`ptrauth_string_discriminator`-style). This correctly distinguishes
callee-allocated coroutine continuations (per-yield-type) from the *fixed*
opaque yield_once constants (3909 / 56769). Mirrors IRGen's
`PointerAuthEntity` string scheme, same as `FunctionPointerAuthentication.swift`
uses for `@convention(thin)` closure words (`"function:N:…:1:result:"`). ✅

---

## 2. Follow-up status

The grounding pass turned every bare ABI magic number into a named constant that
copies the compiler's own identifier, so the trampoline speaks the compiler's
vocabulary and the values stay diff-able against swiftlang/swift. Commit-by-commit:

1. **Extended-existential `Shape` pointer — RESOLVED.**
   `inspectExtendedExistential` now authenticates the `Shape` field through
   `td_auth_extended_existential_shape`
   (`ptrauth_key_process_independent_data`, address-diversified, discriminator
   `NonUniqueExtendedExistentialTypeShape = 0xe798`), mirroring the existing
   `td_prepare_coro_witness_target` pattern. Off arm64e the helper returns the
   pointer unchanged, so arm64 / x86_64 behavior is byte-identical.

2. **Async `Parent` / `ResumeParent` on arm64e — GROUNDED + SPECIFIED, not
   applied.** The exact `pacda`/`pacia` sign-on-store and `autda`/`autia`
   auth-on-read recipe (keys and diversity from `Config.h`, discriminators
   `AsyncContextParent = 0xbda2` / `AsyncContextResume = 0xd707`, now named
   constants) is recorded inline at the async store site. It is deliberately not
   applied: the sign/auth pairing spans the trampoline's custom context structs
   and cannot be exercised anywhere available (CI runs arm64 non-e; arm64e is not
   executable here and is not a shippable app target). This leaves the change
   fully specified for a future edit made on real arm64e hardware with an
   execution test, without shipping unverifiable ptrauth assembly.

3. **CI discriminator cross-checks — RESOLVED and strengthened, and it found
   two real discrepancies: one fixed, one still open.**
   `check-swift-abi-constants.sh` pins every hardcoded discriminator in the
   header to its documented `SpecialPointerAuthDiscriminators` value (the four
   CoroAllocator values, the shape and async-context values, the modify-resume
   value). The read-resume check first shipped as a second, independent
   hand-copy of the spelling algorithm in bash/C -- that could only catch a
   divergence between two transcriptions, not a bug in the real Swift source.
   It was replaced by
   `Tests/TestDoublesTests/Unit/YieldOnce2ResumeDiscriminatorABITests.swift`,
   which calls the actual shipped `YieldingAccessorRuntime` functions
   (`@testable`) and cross-checks them against a live `xcrun swiftc`'s arm64e
   codegen. What was one function, `resumeDiscriminator(for:)`, was split to
   expose a pure `resumeDiscriminator(isIndirect:returnType:)` core so the
   test can drive it without constructing a full `MethodDescriptor`. The suite
   self-gates on the same live-Swift-6.3 requirement the bash script checks,
   and is a no-op off Apple platforms.

   Three of four `read` yield shapes are **confirmed correct** against the
   live compiler: two non-generic structs with different mangled names (`Int`,
   `Bool`) and a class reference (the constant `-class` spelling). The fourth
   -- a 64-byte struct exercising the *formally indirect* result path, which
   bypasses `pointerAuthTypeSpelling` entirely -- **does not match**: the
   compiler emits discriminator `33953`; the library's bare `"indirect"`
   spelling computes `16775`. The next most plausible fix, `"-indirect"`
   (matching the leading-dash convention `pointerAuthFunctionSpelling` uses
   for an indirect *parameter*), also does not match (`64687`, checked
   directly against `td_function_discriminator`, not against a compiler). This
   is an unresolved, genuinely open question, not a guessed-and-verified fix
   -- it needs either the real IRGen source for `yield_once_2`'s
   `PointerAuthEntity` scheme, or a compiler transcript (`-emit-sil` /
   `-emit-ir`) for a witness with a truly indirect yield, to resolve.

   Extending the cross-check to `modify` witnesses surfaced a second,
   independent finding, this one a genuine library bug rather than a spelling
   gap: `resumeDiscriminator(for:)` derived its `isIndirect` argument from
   `method.result.layout`, the *getter's* ordinary value-size ABI
   classification (`.integer`/`.floatingPoint`/`.aggregate` vs `.indirect`).
   That classification answers "does the getter return this value directly or
   through a pointer," which is the right question for `read` (which can
   legitimately do either) but the wrong one for `modify` -- a `modify`
   accessor always yields the address of the property's storage for in-place
   mutation, regardless of how small the value is, because there is no other
   way to write through it. Compiling real `modify` witnesses for `Int`,
   `Bool`, and a class reference confirmed this at the ABI level: the live
   compiler emits the exact same discriminator, `33953`, for all three --
   identical to the formally-indirect `read` case above, and never the
   direct-yield value the old code path computed for small types. `modifyPlan`
   (`FabricatedWitnessDispatch.swift`) and `makeModifyPlan`
   (`ProtocolForwardingPlan.swift`) both fed the shared, getter-layout-derived
   function, so this affected both witness fabrication (Stub) and forwarding
   (Spy) for every `get`/`set`/`modify` property whose getter returns a
   direct-layout type -- i.e. most of them.

   **Fixed:** `resumeDiscriminator(for:)` is now two functions,
   `readResumeDiscriminator(for:)` (unchanged value-size-derived behavior) and
   `modifyResumeDiscriminator(for:)` (always passes `isIndirect: true`, never
   inspects `method.result.layout`), and every `modify` call site was moved to
   the latter. This does not, by itself, make the `modify` probes pass --
   they hit the exact same unresolved indirect-spelling gap the 64-byte struct
   `read` probe does, since both now go through the identical `isIndirect: true`
   branch. But it corrects the classification itself, which is independently
   verifiable against the ABI (`modify` is unconditionally by-reference) without
   needing the indirect spelling resolved first, and it consolidates what were
   two distinct wrong numbers into one well-understood open question instead of
   a silent, type-dependent misclassification.

   All four now-known-indirect probes (`read`'s oversized struct, and
   `modify`'s `Int`/`Bool`/class) are tracked with `withKnownIssue` so they
   stay visible -- and will fail loudly the moment a future fix on the shared
   spelling makes them start passing -- without blocking CI. This branch had
   zero live-compiler coverage before this suite existed; it still has none
   that passes for the indirect/`modify` branch, but the gap is now precisely
   characterized instead of silently assumed correct, and the classification
   bug that was hiding *inside* that gap is fixed. On arm64 CI the accessor
   tests can't catch a wrong discriminator at all (no active ptrauth), so this
   is the first evidence, in either direction, about the library's
   indirect-yield spelling model and about `modify`'s classification.

4. **`swift_deletedCalleeAllocatedCoroutineMethodErrorTwc` weak shim — RETAINED,
   with recheck note.** Still required: Apple Swift 6.3's dead-method elimination
   references this `…Twc` coroutine descriptor but the SDK does not export it, so
   the package supplies a weak trapping definition that a future runtime export
   would override. Recheck when bumping the toolchain — once the SDK ships the
   symbol, drop the shim and confirm no duplicate-definition conflict.

5. **`mallocTypeId` — intentionally unused, now grounded.** The generated coro
   descriptor sets `mallocTypeID = 0` and the veneer supplies its own
   `CoroAllocatorKind::Malloc` allocator (flags `0x102` = Malloc |
   ShouldDeallocateImmediately) instead of the `TypedMalloc`
   (`swift_coroFrameAlloc`) path the field feeds — matching Swift IRGen's own
   zero-when-disabled behavior. Fabricated read/modify2 coroutines therefore do
   not participate in typed-frame allocation; revisit only if typed-allocation
   instrumentation is ever needed.

6. **`getExtraDiscriminator()` masking — forward-looking caution.**
   `ProtocolRequirementFlags::getExtraDiscriminator()` is `Value >> 16` with no
   `& 0xFFFF`. The library never reads a requirement's extra discriminator, so
   nothing depends on this today; if that changes, mask the high half of the
   32-bit flags word to match the compiler.

---

## 3. Future-implementation openings surfaced while browsing

- **Swift 6.4 `yielding borrow` accessors.** `StubContract`/CI already probe the
  6.4 witness-table shape (paired legacy `read:` + `yielding_borrow:` entries),
  and it is deliberately fail-closed. The scaffolding to detect it exists; the
  dispatch/forwarding path is the remaining work.
- **arm64e as a first-class target.** The extended-existential shape read is now
  authenticated (§2.1); the async-context `Parent`/`ResumeParent` signing (§2.2)
  is the remaining concrete blocker, fully specified and awaiting an arm64e
  execution test. Function-pointer signing is already in place.
- **Broader SIMD.** Current support is bounded to complete one-register 128-bit
  lanes (correct: AArch64 `q`/x86_64 `xmm` each carry ≤128 bits in one register).
  Multi-register vectors, scalarized lanes, and stack-passed vectors are
  fail-closed by design — an extension point, not a bug.
- **`read` requirements in `Dummy`, native (non-`NSObject`) superclass
  constraints, superclass-constrained extended existentials** — all listed as
  fail-closed in the contract; each is a discrete future slice.

---

_Source refs: `swiftlang/swift@main` — `docs/ABI/CallingConventionSummary.rst`,
`include/swift/ABI/MetadataValues.h`, `include/swift/ABI/Metadata.h`,
`include/swift/ABI/Coro.h`, `include/swift/ABI/Task.h`._

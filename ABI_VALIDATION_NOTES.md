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

3. **CI discriminator cross-checks — RESOLVED, then strengthened.**
   `check-swift-abi-constants.sh` pins every hardcoded discriminator in the
   header to its documented `SpecialPointerAuthDiscriminators` value (the four
   CoroAllocator values, the shape and async-context values, the modify-resume
   value). The read-resume check first shipped as a second, independent
   hand-copy of the spelling algorithm in bash/C -- that could only catch a
   divergence between two transcriptions, not a bug in the real Swift source.
   It was replaced by
   `Tests/TestDoublesTests/Unit/YieldOnce2ResumeDiscriminatorABITests.swift`,
   which calls the actual shipped `YieldingAccessorRuntime.resumeDiscriminator`
   (`@testable`) and cross-checks it against a live `xcrun swiftc`'s arm64e
   codegen for four distinct yield shapes: two non-generic structs with
   different mangled names (`Int`, `Bool`), a class reference (the constant
   `-class` spelling), and a 64-byte struct (the formally indirect result
   path, which bypasses `pointerAuthTypeSpelling` entirely and was previously
   completely unchecked). `resumeDiscriminator(for:)` was split to expose a
   pure `resumeDiscriminator(isIndirect:returnType:)` core so the test can
   drive it without constructing a full `MethodDescriptor`. The suite
   self-gates on the same live-Swift-6.3 requirement the bash script checks,
   and is a no-op off Apple platforms. On arm64 CI the accessor tests can't
   catch a wrong discriminator (no active ptrauth), so this is the first
   automated check of the library's spelling model against the compiler
   itself, not against another copy of the same assumption.

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

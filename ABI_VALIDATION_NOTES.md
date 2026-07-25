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

## 2. Noteworthy findings / latent gaps (candidates to revisit)

1. **Extended-existential `Shape` pointer is loaded raw.**
   `Metadata.h` declares `TargetExtendedExistentialTypeMetadata::Shape` as
   `__ptrauth_swift_nonunique_extended_existential_type_shape`
   (discriminator `0xe798`). `inspectExtendedExistential` does
   `metadata.load(fromByteOffset: 8, as: UnsafeRawPointer.self)` and dereferences
   it directly. Correct on arm64 / x86_64 (user processes don't sign it), but on
   a genuine arm64e process this needs authentication/stripping. Same pattern as
   the async-context note below. → *Future: an arm64e-safe shape reader.*

2. **Async `Parent` / `ResumeParent` stored unsigned on arm64e.**
   The async trampoline does `stp x11, x8, [x0]` into the callee context's
   `Parent`/`ResumeParent` without the `__ptrauth_swift_async_context_parent`
   (`0xbda2`) / `…_resume` (`0xd707`) signing the runtime uses on arm64e. Fine on
   shippable arm64/x86_64; a real arm64e target would fault. The lib already
   signs *function pointers* on arm64e (`blraa`/`pacia`, `@AUTH`), so this is a
   consistency gap specific to context words. → *Future arm64e async support.*

3. **CI cross-checks the resume discriminators but not the CoroAllocator
   discriminators.** `check-swift-abi-constants.sh` derives and compares the
   modify-resume discriminator, and prints the read-resume one, but the four
   hardcoded `@AUTH` values in `td_swift_read_coro_allocator`
   (24469/40879/53841/23464) are not probed. They match today's Swift, but a
   future rename would drift silently. → *Add a probe, or reference the constants
   symbolically.* Also: the read-resume derivation prints the compiler value but
   does **not** assert equality with `YieldingAccessorRuntime.resumeDiscriminator`'s
   computed hash — worth tightening.

4. **`swift_deletedCalleeAllocatedCoroutineMethodErrorTwc` weak shim.**
   The lib provides a weak trapping `…Twc` descriptor because "Apple Swift 6.3's
   dead-method elimination references it but the SDK does not export it." This is
   a real SDK gap workaround; when a future SDK exports the real symbol the weak
   def yields to it. Worth a periodic recheck so it can be removed once the SDK
   ships it, and to ensure no duplicate-symbol conflict.

5. **`mallocTypeId` in the coro descriptor is intentionally unused.**
   The lib supplies its own `Malloc`-kind allocator rather than the
   `TypedMalloc` (`swift_coroFrameAlloc`) path the `mallocTypeId` feeds. Valid and
   simpler, but means fabricated read/modify2 coroutines don't participate in
   typed allocation. Note if typed-allocation instrumentation ever matters.

6. **`getExtraDiscriminator()` has no mask in current Swift.**
   `ProtocolRequirementFlags::getExtraDiscriminator()` is `Value >> 16` with no
   `& 0xFFFF`. Not something the lib relies on, but if any code starts reading a
   requirement's extra discriminator from a 32-bit flags word, mask it.

---

## 3. Future-implementation openings surfaced while browsing

- **Swift 6.4 `yielding borrow` accessors.** `StubContract`/CI already probe the
  6.4 witness-table shape (paired legacy `read:` + `yielding_borrow:` entries),
  and it is deliberately fail-closed. The scaffolding to detect it exists; the
  dispatch/forwarding path is the remaining work.
- **arm64e as a first-class target.** Items (1) and (2) above are the two
  concrete blockers; the function-pointer signing is already in place.
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

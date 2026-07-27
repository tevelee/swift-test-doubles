#ifndef TEST_DOUBLES_TRAMPOLINE_H
#define TEST_DOUBLES_TRAMPOLINE_H

#define TD_GP_REGISTER_COUNT 16
#define TD_FP_REGISTER_COUNT 16

#define TD_FRAME_SIZE 544
#define TD_FRAME_SLOT_OFFSET 0
#define TD_FRAME_CONTEXT_OFFSET 8
#define TD_FRAME_GP_OFFSET 16
#define TD_FRAME_FP_OFFSET 144
#define TD_FRAME_STACK_POINTER_OFFSET 400
#define TD_FRAME_INDIRECT_RESULT_OFFSET 408
#define TD_FRAME_SWIFT_SELF_OFFSET 416
#define TD_FRAME_SWIFT_ERROR_OFFSET 424
#define TD_FRAME_RESERVED_OFFSET 432
#define TD_FRAME_RETURN_GP_OFFSET 440
#define TD_FRAME_RETURN_FP_OFFSET 472
#define TD_FRAME_RETURN_ERROR_OFFSET 504
#define TD_FRAME_RETURN_FP_HIGH_OFFSET 512

#define TD_ASYNC_CONTEXT_CALLEE_OFFSET 16
#define TD_ASYNC_CONTEXT_STATE_OFFSET 24
#define TD_ASYNC_CONTEXT_SIZE 32

#define TD_ASYNC_INVOKE_STACK_ARGUMENTS_OFFSET 56
#define TD_ASYNC_INVOKE_CONTEXT_SIZE 64

#define TD_ASYNC_WITNESS_MAX_VISIBLE_STACK_WORDS 4
#define TD_ASYNC_WITNESS_VISIBLE_OFFSET 0
#define TD_ASYNC_WITNESS_METADATA_OFFSET 32
#define TD_ASYNC_WITNESS_TABLE_OFFSET 40
#define TD_ASYNC_WITNESS_VISIBLE_COUNT_OFFSET 48
#define TD_ASYNC_WITNESS_STACK_BYTE_COUNT_OFFSET 56
#define TD_ASYNC_WITNESS_STACK_ARGUMENTS_SIZE 64

#define TD_ASYNC_COMPLETION_FRAME_SIZE 560
#define TD_ASYNC_COMPLETION_PARENT_OFFSET 544
#define TD_ASYNC_COMPLETION_STATE_OFFSET 552

#define TD_MODIFY_CONTEXT_STATE_OFFSET 0
#define TD_MODIFY_CONTEXT_SIZE 32

#define TD_READ_CONTEXT_STATE_OFFSET 0
#define TD_READ_CONTEXT_SIZE 16

// Pointer-authentication discriminators: verbatim copies of
// swiftlang/swift's `SpecialPointerAuthDiscriminators`
// (include/swift/ABI/MetadataValues.h), named to match so they stay
// cross-checkable. `TD_PTRAUTH_OPAQUE_MODIFY_RESUME_FUNCTION` is verified
// live by Scripts/check-swift-abi-constants.sh -- keep its `#define` grep in
// sync when renaming.

// OpaqueModifyResumeFunction: the resume function of a caller-allocated
// (legacy yield_once) `_modify` coroutine yielding one opaque inout value.
// Signed with ptrauth_key_function_pointer, blended with the caller-provided
// coroutine context address.
#define TD_PTRAUTH_OPAQUE_MODIFY_RESUME_FUNCTION 3909

// Function pointers stored in a `swift::CoroAllocator` (include/swift/ABI/Coro.h).
// All four are signed with ptrauth_key_function_pointer (`ia`) and address
// diversity against their slot in the allocator struct.
#define TD_PTRAUTH_CORO_ALLOCATION_FUNCTION 24469
#define TD_PTRAUTH_CORO_DEALLOCATION_FUNCTION 40879
#define TD_PTRAUTH_CORO_FRAME_ALLOCATION_FUNCTION 53841
#define TD_PTRAUTH_CORO_FRAME_DEALLOCATION_FUNCTION 23464

// NonUniqueExtendedExistentialTypeShape: the `Shape` pointer inside a
// TargetExtendedExistentialTypeMetadata (Metadata.h). Signed with
// ptrauth_key_process_independent_data and address diversity against the shape
// field's storage location (__ptrauth_swift_nonunique_extended_existential_type_shape,
// include/swift/Runtime/Config.h).
#define TD_PTRAUTH_NONUNIQUE_EXTENDED_EXISTENTIAL_TYPE_SHAPE 0xe798

// AsyncContext head fields (include/swift/ABI/Task.h): `Parent` at offset 0 and
// `ResumeParent` at offset 8. `Parent` is signed with
// ptrauth_key_process_independent_data (__ptrauth_swift_async_context_parent);
// `ResumeParent` with ptrauth_key_function_pointer
// (__ptrauth_swift_async_context_resume). Both are address-diversified against
// their own storage slot. See the async-entry note in TestDoublesTrampoline.S
// for why the arm64e signing these describe is grounded but not yet applied.
#define TD_PTRAUTH_ASYNC_CONTEXT_PARENT 0xbda2
#define TD_PTRAUTH_ASYNC_CONTEXT_RESUME 0xd707

// TypeDescriptor: the field Swift's ABI declares as
// `TargetContextDescriptor * __ptrauth_swift_type_descriptor`. Signed with
// ptrauth_key_process_independent_data and address diversity against the
// field's own storage location. Authenticates a fabricated conformance
// descriptor's indirect type-descriptor cell (ProtocolConformanceDescriptor
// -> TypeRef -> IndirectTypeDescriptor, Metadata.h / MetadataRef.h).
#define TD_PTRAUTH_TYPE_DESCRIPTOR 0xae86

#ifndef __ASSEMBLER__
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TDVectorRegister {
  uint64_t low;
  uint64_t high;
} TDVectorRegister;

// The assembly bridge captures 64-bit arm64/x86_64 registers even when the
// target uses 32-bit pointers, as watchOS arm64_32 does. Fixed-width slots keep
// the C and assembly layouts identical on every supported compilation target.
typedef struct TDCallFrame {
  uint64_t slot;
  uint64_t context;
  uint64_t gp[TD_GP_REGISTER_COUNT];
  TDVectorRegister fp[TD_FP_REGISTER_COUNT];
  uint64_t stackPointer;
  uint64_t indirectResult;
  uint64_t swiftSelf;
  uint64_t swiftError;
  uint64_t reserved;
  // The 4-word direct-return capacity below (both GP and FP) matches observed
  // arm64/x86_64 compiler output for every direct (non-indirect) result this
  // package has exercised, but the cap itself is decided by Clang's
  // SwiftCallingConv.cpp, outside both this checkout and the Swift repo
  // entirely -- docs/ABI/CallingConvention.rst only describes the philosophy
  // ("one or two more registers to the result"), not a hard number. Treat as
  // an empirical constant, not a documented ABI guarantee.
  uint64_t returnGP[4];
  uint64_t returnFP[4];
  uint64_t returnError;
  uint64_t returnFPHigh[4];
} TDCallFrame;

typedef struct TDSwiftErrorAllocation {
  const void *error;
  void *value;
} TDSwiftErrorAllocation;

typedef struct TDSwiftErrorValue {
  const void *value;
  const void *type;
  const void *witnessTable;
} TDSwiftErrorValue;

typedef struct TDMetadataResponse {
  const void *metadata;
  uintptr_t state;
} TDMetadataResponse;

typedef bool (*TDLocalSymbolVisitor)(const char *name,
                                     const void *address,
                                     void *context);

/// The result of beginning a Swift `_modify` coroutine.
///
/// `state` must remain valid until `td_swift_modify_trampoline_resume_handler`
/// receives it. `yieldedStorage` is returned directly to the Swift caller as
/// the inout storage yielded by the coroutine.
typedef struct TDModifyCoroutineResult {
  void *state;
  void *yieldedStorage;
} TDModifyCoroutineResult;

/// The result of beginning a Swift 6.3 yield_once_2 `read` coroutine.
///
/// `state` is consumed by the resume handler. `yieldedStorage` is non-null
/// only for a formally indirect result, where Swift borrows the initialized
/// value through that address instead of receiving direct register words.
typedef struct TDReadCoroutineResult {
  void *state;
  void *yieldedStorage;
} TDReadCoroutineResult;

/// The result of preparing one async witness dispatch.
///
/// `stackAdjustment` is the 16-byte-aligned distance from async witness entry
/// SP to caller continuation SP. The entry trampoline applies it exactly once
/// before branching to either the immediate continuation or the dispatcher.
typedef struct TDAsyncTrampolineResult {
  void *state;
  uint64_t stackAdjustment;
} TDAsyncTrampolineResult;

/// The bounded outgoing stack payload for an async forwarding witness call.
///
/// Swift 6.3 places up to four visible general-purpose spills first, followed
/// by the target's dynamic-Self metadata and protocol witness table. Assembly
/// adds the architecture-specific alignment or implicit slot around these
/// words. `visibleCount` and `outgoingStackByteCount` are retained with the
/// copied payload so assembly never reads the vanished caller stack.
typedef struct TDAsyncWitnessStackArguments {
  uint64_t visible[TD_ASYNC_WITNESS_MAX_VISIBLE_STACK_WORDS];
  uint64_t metadata;
  uint64_t witnessTable;
  uint64_t visibleCount;
  uint64_t outgoingStackByteCount;
} TDAsyncWitnessStackArguments;

/// Authenticated Swift 6.3 yield_once_2 witness entry information.
///
/// `entry` is the raw relative entry address from the authenticated descriptor.
/// The assembly caller signs it with the descriptor slot and declaration
/// discriminator immediately before invocation.
typedef struct TDCoroWitnessTarget {
  const void *entry;
  uint32_t callerFrameSize;
  uint32_t reserved;
} TDCoroWitnessTarget;

typedef struct TDWitnessVeneerArena TDWitnessVeneerArena;

TDWitnessVeneerArena *td_witness_veneer_arena_create(void);
void *td_witness_veneer_arena_make_witness(TDWitnessVeneerArena *arena,
                                           uintptr_t slot,
                                           uintptr_t context);
void *td_witness_veneer_arena_make_async(TDWitnessVeneerArena *arena,
                                         uintptr_t slot,
                                         uintptr_t context);
void *td_witness_veneer_arena_make_modify(TDWitnessVeneerArena *arena,
                                          uintptr_t slot,
                                          uintptr_t context);
void *td_witness_veneer_arena_make_modify_descriptor(
    TDWitnessVeneerArena *arena,
    uintptr_t slot,
    uintptr_t context,
    uint16_t resumeDiscriminator);
void *td_witness_veneer_arena_make_read(TDWitnessVeneerArena *arena,
                                        uintptr_t slot,
                                        uintptr_t context,
                                        uint16_t resumeDiscriminator);
void *td_witness_veneer_arena_make_typed(
    TDWitnessVeneerArena *arena,
    const void *target,
    uintptr_t invocation,
    uintptr_t invocationArgumentIndex);
void *td_witness_veneer_arena_make_typed_async(
    TDWitnessVeneerArena *arena,
    const void *target,
    uintptr_t invocation,
    uintptr_t invocationArgumentIndex);
bool td_witness_veneer_arena_publish(TDWitnessVeneerArena *arena);
size_t td_witness_veneer_arena_page_count(const TDWitnessVeneerArena *arena);
void td_witness_veneer_arena_destroy(TDWitnessVeneerArena *arena);
const char *td_symbol_name(const void *address);
const char *td_exact_symbol_name(const void *address);
const void *td_symbol_address(const char *name);
void td_visit_local_symbols(TDLocalSymbolVisitor visitor, void *context);
const void *td_sign_function_pointer(const void *pointer, uint16_t discriminator);
const void *td_sign_async_function_pointer(const void *pointer,
                                           uint16_t discriminator);
const void *td_sign_coro_witness_pointer(const void *pointer,
                                         const void *slot,
                                         uint16_t discriminator);
const void *td_sign_modify_witness_pointer(const void *pointer,
                                           const void *slot,
                                           uint16_t discriminator);
const void *td_sign_type_descriptor_pointer(const void *pointer,
                                            const void *slot);
bool td_prepare_coro_witness_target(const void *signedDescriptor,
                                    const void *slot,
                                    uint16_t declarationDiscriminator,
                                    TDCoroWitnessTarget *result);
/// Authenticates the `Shape` pointer of an extended-existential type metadata.
///
/// `storageAddress` is the address of the shape field within the metadata
/// record (the metadata pointer plus one word). On pointer-authenticated
/// targets the shape is signed with
/// `__ptrauth_swift_nonunique_extended_existential_type_shape`; elsewhere the
/// pointer is returned unchanged.
const void *td_auth_extended_existential_shape(const void *signedShape,
                                               const void *storageAddress);
const void *td_strip_witness_function_pointer(const void *pointer);
const void *td_strip_async_witness_pointer(const void *pointer);
uint16_t td_generic_function_discriminator(uint16_t parameterCount,
                                           bool hasResult);
uint16_t td_function_discriminator(const uint8_t *spelling, size_t length);
void td_swift_retain(const void *object);
void td_swift_release(const void *object);
void td_swift_invoke_function(const void *function,
                              const void *context,
                              uint16_t discriminator,
                              TDCallFrame *frame);
/// Invokes a witness function, optionally spilling up to two caller-owned
/// outgoing stack words first.
///
/// `outgoingStackWord1`/`outgoingStackWord2` are passed as explicit
/// parameters rather than through `frame` so this never touches
/// `TDCallFrame`'s layout: forwarding calls that need zero stack words pass
/// zero for both, harmlessly. Reserved and written even when unused; the
/// callee only reads as many words as its own signature has.
void td_swift_invoke_witness(const void *function,
                             const void *self,
                             TDCallFrame *frame,
                             uint64_t outgoingStackWord1,
                             uint64_t outgoingStackWord2);
TDReadCoroutineResult td_swift_invoke_read_witness(
    const void *entry,
    const void *slot,
    uint16_t declarationDiscriminator,
    const void *self,
    TDCallFrame *frame,
    void *callerFrame);
void td_swift_resume_read_witness(const void *resume,
                                  void *callerFrame,
                                  uint16_t resumeDiscriminator);
TDModifyCoroutineResult td_swift_invoke_modify_witness(
    const void *entry,
    const void *slot,
    uint16_t declarationDiscriminator,
    const void *self,
    TDCallFrame *frame,
    void *callerFrame);
void td_swift_resume_modify_witness(const void *resume,
                                    void *callerFrame,
                                    bool isAborting);
const void *td_swift_dynamic_async_function_descriptor(void);
void td_swift_get_error_value(const void *error,
                              void **scratch,
                              TDSwiftErrorValue *result);
void td_swift_error_release(const void *error);
void td_swift_trampoline_entry(void);
void td_swift_dynamic_function_entry(void);
void td_swift_dynamic_async_function_entry(void);
void td_swift_async_trampoline_entry(void);
void td_swift_modify_trampoline_entry(void);
void td_swift_modify_trampoline_resume(void);
void td_swift_modify_descriptor_trampoline_entry(void);
void td_swift_modify_descriptor_trampoline_resume(void);
void td_swift_read_trampoline_entry(void);
void td_swift_read_trampoline_resume(void);
void td_swift_trampoline_handler(TDCallFrame *frame);
void td_swift_dynamic_function_handler(TDCallFrame *frame);
TDAsyncTrampolineResult td_swift_async_trampoline_handler(TDCallFrame *frame);
void td_swift_async_dispatch_finish(void *state, TDCallFrame *frame);

/// Begins a `_modify` dispatch captured in `frame`.
///
/// `frame.slot` and `frame.context` identify the generated veneer. `frame.gp[0]`
/// is Swift's caller-provided 32-byte coroutine context; user arguments begin at
/// `frame.gp[1]`, and `frame.swiftSelf` contains the Swift self register.
///
/// The implementation owns `result.state` until the resume handler is called
/// exactly once. It must provide writable storage that remains valid for that
/// entire interval. The assembly bridge stores `result.state` in the first word
/// of Swift's 32-byte caller-provided coroutine context.
TDModifyCoroutineResult td_swift_modify_trampoline_handler(TDCallFrame *frame);

/// Completes or aborts a `_modify` dispatch and consumes `state`.
///
/// `isAborting` is the Swift coroutine abort flag. Implementations must perform
/// any required writeback and release the state on both paths.
void td_swift_modify_trampoline_resume_handler(void *state, bool isAborting);

/// Begins a Swift 6.3 `read` dispatch captured in `frame`.
///
/// The generated descriptor supplies a 16-byte caller frame. User arguments
/// begin after that hidden frame (and the x86_64 allocator argument). The
/// implementation retains the yielded value until the resume handler consumes
/// `result.state` exactly once on either normal completion or abort.
TDReadCoroutineResult td_swift_read_trampoline_handler(TDCallFrame *frame);
void td_swift_read_trampoline_resume_handler(void *state, bool isAborting);
TDSwiftErrorAllocation td_swift_alloc_error(const void *type,
                                            const void *witnessTable,
                                            const void *flags,
                                            bool isTake);
/// Reconstructs tuple type metadata for any element count. `elements` points
/// to `count` element metadata pointers; `count` is folded into the real
/// runtime entry point's flags word verbatim (`TupleTypeFlags`'s low 16 bits
/// are the raw element count, confirmed against swiftlang/swift's
/// include/swift/ABI/MetadataValues.h -- no shift, no other bits needed since
/// this library's label pointers are always permanently retained, matching
/// flags bit 16 left at 0).
TDMetadataResponse td_swift_get_tuple_type_metadata(uintptr_t request,
                                                     const void *const *elements,
                                                     uintptr_t count,
                                                     const char *labels);

#ifdef __cplusplus
}
#endif

#endif /* !__ASSEMBLER__ */
#endif

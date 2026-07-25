#include "TestDoublesTrampoline.h"
#include "RuntimeDescriptorLayout.h"

#include <stddef.h>
#include <stdint.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

extern TDSwiftErrorAllocation swift_allocError(const void *type,
                                               const void *witnessTable,
                                               const void *flags,
                                               bool isTake);
extern void swift_getErrorValue(const void *error,
                                void **scratch,
                                TDSwiftErrorValue *result);
extern void swift_errorRelease(const void *error);
extern void *swift_retain(const void *object);
extern void swift_release(const void *object);
extern const uint32_t td_swift_dynamic_async_function_entryTu[];

#if __has_attribute(swiftcall)
#define TD_SWIFT_CC __attribute__((swiftcall))
#else
#define TD_SWIFT_CC
#endif

// swift_getTupleTypeMetadata is the general entry point behind the fixed
// -2/-3 convenience wrappers Swift's own compiler emits calls to; `flags`
// carries the element count (TupleTypeFlags's low 16 bits, unshifted) so
// this one function covers every arity, not just 2 and 3.
extern TDMetadataResponse swift_getTupleTypeMetadata(
    uintptr_t request, uintptr_t flags, const void *const *elements,
    const char *labels, const void *proposedWitnesses) TD_SWIFT_CC;

_Static_assert(sizeof(TDCallFrame) == TD_FRAME_SIZE, "TDCallFrame size changed");
_Static_assert(offsetof(TDCallFrame, slot) == TD_FRAME_SLOT_OFFSET,
               "slot offset changed");
_Static_assert(offsetof(TDCallFrame, context) == TD_FRAME_CONTEXT_OFFSET,
               "context offset changed");
_Static_assert(offsetof(TDCallFrame, gp) == TD_FRAME_GP_OFFSET,
               "gp offset changed");
_Static_assert(offsetof(TDCallFrame, fp) == TD_FRAME_FP_OFFSET,
               "fp offset changed");
_Static_assert(offsetof(TDCallFrame, stackPointer) ==
                   TD_FRAME_STACK_POINTER_OFFSET,
               "stackPointer offset changed");
_Static_assert(offsetof(TDCallFrame, indirectResult) ==
                   TD_FRAME_INDIRECT_RESULT_OFFSET,
               "indirectResult offset changed");
_Static_assert(offsetof(TDCallFrame, swiftSelf) == TD_FRAME_SWIFT_SELF_OFFSET,
               "swiftSelf offset changed");
_Static_assert(offsetof(TDCallFrame, swiftError) == TD_FRAME_SWIFT_ERROR_OFFSET,
               "swiftError offset changed");
_Static_assert(offsetof(TDCallFrame, reserved) == TD_FRAME_RESERVED_OFFSET,
               "reserved offset changed");
_Static_assert(offsetof(TDCallFrame, returnGP) == TD_FRAME_RETURN_GP_OFFSET,
               "returnGP offset changed");
_Static_assert(offsetof(TDCallFrame, returnFP) == TD_FRAME_RETURN_FP_OFFSET,
               "returnFP offset changed");
_Static_assert(offsetof(TDCallFrame, returnError) ==
                   TD_FRAME_RETURN_ERROR_OFFSET,
               "returnError offset changed");
_Static_assert(offsetof(TDCallFrame, returnFPHigh) ==
                   TD_FRAME_RETURN_FP_HIGH_OFFSET,
               "returnFPHigh offset changed");
_Static_assert(sizeof(TDAsyncWitnessStackArguments) == 3 * sizeof(uint64_t),
               "async witness stack arguments size changed");
_Static_assert(offsetof(TDAsyncWitnessStackArguments, visible) == 0,
               "async witness visible stack word offset changed");
_Static_assert(offsetof(TDAsyncWitnessStackArguments, metadata) == 8,
               "async witness metadata stack word offset changed");
_Static_assert(offsetof(TDAsyncWitnessStackArguments, witnessTable) == 16,
               "async witness table stack word offset changed");
_Static_assert(sizeof(TDModifyCoroutineResult) == 2 * sizeof(void *),
               "TDModifyCoroutineResult size changed");
_Static_assert(sizeof(TDReadCoroutineResult) == 2 * sizeof(void *),
               "TDReadCoroutineResult size changed");
_Static_assert(sizeof(TDCoroWitnessTarget) ==
                   sizeof(void *) + 2 * sizeof(uint32_t),
               "TDCoroWitnessTarget size changed");

#if __has_attribute(weak)
#define TD_WEAK __attribute__((weak))
#else
#define TD_WEAK
#endif

/// Fail-closed hooks until the Swift runtime installs the strong definitions.
/// A generated modify veneer is safe to allocate before that integration, but
/// executing it cannot fabricate writable yielded storage or retained state.
TD_WEAK TDModifyCoroutineResult
td_swift_modify_trampoline_handler(TDCallFrame *frame) {
  (void)frame;
  __builtin_trap();
}

TD_WEAK void td_swift_modify_trampoline_resume_handler(void *state,
                                                       bool isAborting) {
  (void)state;
  (void)isAborting;
  __builtin_trap();
}

TD_WEAK TDReadCoroutineResult
td_swift_read_trampoline_handler(TDCallFrame *frame) {
  (void)frame;
  __builtin_trap();
}

TD_WEAK void td_swift_read_trampoline_resume_handler(void *state,
                                                     bool isAborting) {
  (void)state;
  (void)isAborting;
  __builtin_trap();
}

TD_WEAK void td_swift_dynamic_function_handler(TDCallFrame *frame) {
  (void)frame;
  __builtin_trap();
}

const void *td_sign_coro_witness_pointer(const void *pointer, const void *slot,
                                         uint16_t discriminator) {
#if defined(__APPLE__) && __has_feature(ptrauth_calls)
  uintptr_t blended = ptrauth_blend_discriminator(slot, discriminator);
  return ptrauth_sign_unauthenticated(
      pointer, ptrauth_key_process_dependent_data, blended);
#else
  (void)slot;
  (void)discriminator;
  return pointer;
#endif
}

const void *td_sign_modify_witness_pointer(const void *pointer,
                                           const void *slot,
                                           uint16_t discriminator) {
#if defined(__APPLE__) && __has_feature(ptrauth_calls)
  uintptr_t blended = ptrauth_blend_discriminator(slot, discriminator);
  return ptrauth_sign_unauthenticated(
      pointer, ptrauth_key_function_pointer, blended);
#else
  (void)slot;
  (void)discriminator;
  return pointer;
#endif
}

bool td_prepare_coro_witness_target(const void *signedDescriptor,
                                    const void *slot,
                                    uint16_t declarationDiscriminator,
                                    TDCoroWitnessTarget *result) {
  if (!signedDescriptor || !slot || !result) {
    return false;
  }

  const TDCoroFunctionPointer *descriptor = signedDescriptor;
#if defined(__APPLE__) && __has_feature(ptrauth_calls)
  uintptr_t blended =
      ptrauth_blend_discriminator(slot, declarationDiscriminator);
  descriptor = ptrauth_auth_data(
      descriptor, ptrauth_key_process_dependent_data, blended);
#else
  (void)declarationDiscriminator;
#endif

  if (!descriptor->relativeFunction || !descriptor->callerFrameSize) {
    return false;
  }
  result->entry = (const uint8_t *)descriptor + descriptor->relativeFunction;
  result->callerFrameSize = descriptor->callerFrameSize;
  result->reserved = 0;
  return true;
}

void td_swift_retain(const void *object) {
  if (object) {
    swift_retain(object);
  }
}

void td_swift_release(const void *object) {
  if (object) {
    swift_release(object);
  }
}

const void *td_swift_dynamic_async_function_descriptor(void) {
  return td_swift_dynamic_async_function_entryTu;
}

void td_swift_get_error_value(const void *error, void **scratch,
                              TDSwiftErrorValue *result) {
  swift_getErrorValue(error, scratch, result);
}

void td_swift_error_release(const void *error) {
  if (error) {
    swift_errorRelease(error);
  }
}

TDSwiftErrorAllocation td_swift_alloc_error(const void *type,
                                            const void *witnessTable,
                                            const void *flags, bool isTake) {
  return swift_allocError(type, witnessTable, flags, isTake);
}

TDMetadataResponse td_swift_get_tuple_type_metadata(uintptr_t request,
                                                     const void *const *elements,
                                                     uintptr_t count,
                                                     const char *labels) {
  return swift_getTupleTypeMetadata(request, count, elements, labels, 0);
}

#ifndef TEST_DOUBLES_TRAMPOLINE_H
#define TEST_DOUBLES_TRAMPOLINE_H

#define TD_GP_REGISTER_COUNT 16
#define TD_FP_REGISTER_COUNT 16

#define TD_FRAME_SIZE 512
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

#define TD_ASYNC_CONTEXT_CALLEE_OFFSET 16
#define TD_ASYNC_CONTEXT_STATE_OFFSET 24
#define TD_ASYNC_CONTEXT_SIZE 32

#define TD_ASYNC_COMPLETION_FRAME_SIZE 528
#define TD_ASYNC_COMPLETION_PARENT_OFFSET 512
#define TD_ASYNC_COMPLETION_STATE_OFFSET 520

#ifndef __ASSEMBLER__
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TDVectorRegister {
  uint64_t low;
  uint64_t high;
} TDVectorRegister;

typedef struct TDCallFrame {
  uintptr_t slot;
  uintptr_t context;
  uintptr_t gp[TD_GP_REGISTER_COUNT];
  TDVectorRegister fp[TD_FP_REGISTER_COUNT];
  uintptr_t stackPointer;
  uintptr_t indirectResult;
  uintptr_t swiftSelf;
  uintptr_t swiftError;
  uintptr_t reserved;
  uintptr_t returnGP[4];
  uint64_t returnFP[4];
  uintptr_t returnError;
} TDCallFrame;

typedef struct TDSwiftErrorAllocation {
  const void *error;
  void *value;
} TDSwiftErrorAllocation;

typedef struct TDMetadataResponse {
  const void *metadata;
  uintptr_t state;
} TDMetadataResponse;

void *td_make_witness_trampoline(uintptr_t slot, uintptr_t context);
void *td_make_async_witness_trampoline(uintptr_t slot, uintptr_t context);
void td_free_witness_trampoline(void *ptr);
const char *td_symbol_name(const void *address);
void td_swift_trampoline_entry(void);
void td_swift_async_trampoline_entry(void);
void td_swift_trampoline_handler(TDCallFrame *frame);
void *td_swift_async_trampoline_handler(TDCallFrame *frame);
void td_swift_async_dispatch_finish(void *state, TDCallFrame *frame);
TDSwiftErrorAllocation td_swift_alloc_error(const void *type,
                                            const void *witnessTable,
                                            const void *flags,
                                            bool isTake);
TDMetadataResponse td_swift_get_tuple_type_metadata2(uintptr_t request,
                                                     const void *first,
                                                     const void *second,
                                                     const char *labels);
TDMetadataResponse td_swift_get_tuple_type_metadata3(uintptr_t request,
                                                     const void *first,
                                                     const void *second,
                                                     const void *third,
                                                     const char *labels);

#ifdef __cplusplus
}
#endif

#endif /* !__ASSEMBLER__ */
#endif

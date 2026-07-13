#ifndef TEST_DOUBLES_TRAMPOLINE_H
#define TEST_DOUBLES_TRAMPOLINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TD_GP_REGISTER_COUNT 16
#define TD_FP_REGISTER_COUNT 16
#define TD_STACK_ARGUMENT_BYTES 512

typedef struct TDVectorRegister {
  uint64_t low;
  uint64_t high;
} TDVectorRegister;

typedef struct TDCallFrame {
  uintptr_t slot;
  uintptr_t reserved0;
  uintptr_t gp[TD_GP_REGISTER_COUNT];
  TDVectorRegister fp[TD_FP_REGISTER_COUNT];
  uint8_t stack[TD_STACK_ARGUMENT_BYTES];
  uintptr_t stackPointer;
  uintptr_t indirectResult;
  uintptr_t swiftSelf;
  uintptr_t swiftError;
  uintptr_t witnessTable;
  uintptr_t returnGP[4];
  uint64_t returnFP[4];
  uintptr_t returnError;
} TDCallFrame;

typedef struct TDSwiftErrorAllocation {
  const void *error;
  void *value;
} TDSwiftErrorAllocation;

void *td_make_witness_trampoline(uintptr_t slot, uintptr_t context);
void td_free_witness_trampoline(void *ptr);
void td_swift_trampoline_entry(void);
void td_swift_trampoline_handler(TDCallFrame *frame);
TDSwiftErrorAllocation td_swift_alloc_error(const void *type,
                                            const void *witnessTable,
                                            const void *flags,
                                            bool isTake);

#ifdef __cplusplus
}
#endif

#endif

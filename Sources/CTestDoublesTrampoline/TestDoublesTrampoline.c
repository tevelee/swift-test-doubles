#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "TestDoublesTrampoline.h"

#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if !defined(MAP_ANON) && defined(MAP_ANONYMOUS)
#define MAP_ANON MAP_ANONYMOUS
#endif

extern TDSwiftErrorAllocation swift_allocError(const void *type,
                                               const void *witnessTable,
                                               const void *flags,
                                               bool isTake);

#if __has_attribute(swiftcall)
#define TD_SWIFT_CC __attribute__((swiftcall))
#else
#define TD_SWIFT_CC
#endif

extern TDMetadataResponse swift_getTupleTypeMetadata2(uintptr_t request,
                                                      const void *first,
                                                      const void *second,
                                                      const char *labels,
                                                      const void *proposedWitnesses)
    TD_SWIFT_CC;
extern TDMetadataResponse swift_getTupleTypeMetadata3(uintptr_t request,
                                                      const void *first,
                                                      const void *second,
                                                      const void *third,
                                                      const char *labels,
                                                      const void *proposedWitnesses)
    TD_SWIFT_CC;

_Static_assert(sizeof(TDCallFrame) == TD_FRAME_SIZE, "TDCallFrame size changed");
_Static_assert(offsetof(TDCallFrame, slot) == TD_FRAME_SLOT_OFFSET, "slot offset changed");
_Static_assert(offsetof(TDCallFrame, context) == TD_FRAME_CONTEXT_OFFSET, "context offset changed");
_Static_assert(offsetof(TDCallFrame, gp) == TD_FRAME_GP_OFFSET, "gp offset changed");
_Static_assert(offsetof(TDCallFrame, fp) == TD_FRAME_FP_OFFSET, "fp offset changed");
_Static_assert(offsetof(TDCallFrame, stackPointer) == TD_FRAME_STACK_POINTER_OFFSET, "stackPointer offset changed");
_Static_assert(offsetof(TDCallFrame, indirectResult) == TD_FRAME_INDIRECT_RESULT_OFFSET, "indirectResult offset changed");
_Static_assert(offsetof(TDCallFrame, swiftSelf) == TD_FRAME_SWIFT_SELF_OFFSET, "swiftSelf offset changed");
_Static_assert(offsetof(TDCallFrame, swiftError) == TD_FRAME_SWIFT_ERROR_OFFSET, "swiftError offset changed");
_Static_assert(offsetof(TDCallFrame, reserved) == TD_FRAME_RESERVED_OFFSET, "reserved offset changed");
_Static_assert(offsetof(TDCallFrame, returnGP) == TD_FRAME_RETURN_GP_OFFSET, "returnGP offset changed");
_Static_assert(offsetof(TDCallFrame, returnFP) == TD_FRAME_RETURN_FP_OFFSET, "returnFP offset changed");
_Static_assert(offsetof(TDCallFrame, returnError) == TD_FRAME_RETURN_ERROR_OFFSET, "returnError offset changed");

static size_t td_page_size(void) {
  long pageSize = sysconf(_SC_PAGESIZE);
  return pageSize > 0 ? (size_t)pageSize : (size_t)16384;
}

static void *td_allocate_code_page(size_t *size) {
  *size = td_page_size();
  int flags = MAP_PRIVATE | MAP_ANON;
#if defined(MAP_JIT)
  flags |= MAP_JIT;
#endif
  void *ptr = mmap(0, *size, PROT_READ | PROT_WRITE, flags, -1, 0);
  if (ptr == MAP_FAILED) {
    return 0;
  }
  return ptr;
}

static void td_publish_code(void *ptr, size_t size) {
  __builtin___clear_cache((char *)ptr, (char *)ptr + size);
  (void)mprotect(ptr, size, PROT_READ | PROT_EXEC);
}

#if defined(__aarch64__) || defined(__arm64__)
static uint32_t td_arm64_movz(unsigned reg, uint64_t value, unsigned halfword) {
  return 0xd2800000u | (halfword << 21) | ((uint32_t)(value & 0xffffu) << 5) | reg;
}

static uint32_t td_arm64_movk(unsigned reg, uint64_t value, unsigned halfword) {
  return 0xf2800000u | (halfword << 21) | ((uint32_t)(value & 0xffffu) << 5) | reg;
}

static void td_arm64_emit_movabs(uint32_t **cursor, unsigned reg, uintptr_t value) {
  uint64_t v = (uint64_t)value;
  *(*cursor)++ = td_arm64_movz(reg, v, 0);
  *(*cursor)++ = td_arm64_movk(reg, v >> 16, 1);
  *(*cursor)++ = td_arm64_movk(reg, v >> 32, 2);
  *(*cursor)++ = td_arm64_movk(reg, v >> 48, 3);
}
#elif defined(__x86_64__)
static void td_x86_emit_movabs(uint8_t **cursor, uint8_t opcode, uintptr_t value) {
  *(*cursor)++ = 0x49;
  *(*cursor)++ = opcode;
  uint64_t immediate = (uint64_t)value;
  memcpy(*cursor, &immediate, sizeof(immediate));
  *cursor += sizeof(immediate);
}

static void td_x86_emit_absolute_jump(uint8_t **cursor, const void *target) {
  *(*cursor)++ = 0xff;
  *(*cursor)++ = 0x25; /* jmpq *0(%rip) */
  *(*cursor)++ = 0x00;
  *(*cursor)++ = 0x00;
  *(*cursor)++ = 0x00;
  *(*cursor)++ = 0x00;
  uint64_t address = (uint64_t)(uintptr_t)target;
  memcpy(*cursor, &address, sizeof(address));
  *cursor += sizeof(address);
}
#endif

typedef struct TDAsyncFunctionPointer {
  int32_t relativeFunction;
  uint32_t expectedContextSize;
} TDAsyncFunctionPointer;

_Static_assert(sizeof(TDAsyncFunctionPointer) == 8, "async function descriptor size changed");
_Static_assert(offsetof(TDAsyncFunctionPointer, relativeFunction) == 0,
               "async function descriptor relative function offset changed");
_Static_assert(offsetof(TDAsyncFunctionPointer, expectedContextSize) == 4,
               "async function descriptor context size offset changed");

void *td_make_witness_trampoline(uintptr_t slot, uintptr_t context) {
  size_t pageSize = 0;
  uint8_t *code = td_allocate_code_page(&pageSize);
  if (!code) {
    return 0;
  }

#if defined(__aarch64__) || defined(__arm64__)
  uint32_t *cursor = (uint32_t *)code;
  td_arm64_emit_movabs(&cursor, 15, context);
  td_arm64_emit_movabs(&cursor, 16, slot);
  td_arm64_emit_movabs(&cursor, 17, (uintptr_t)&td_swift_trampoline_entry);
  *cursor++ = 0xd61f0220u; /* br x17 */
#elif defined(__x86_64__)
  uint8_t *cursor = code;
  td_x86_emit_movabs(&cursor, 0xbb, slot); /* movabs imm64, %r11 */
  td_x86_emit_movabs(&cursor, 0xba, context); /* movabs imm64, %r10 */
  td_x86_emit_absolute_jump(&cursor, (const void *)&td_swift_trampoline_entry);
#else
  munmap(code, pageSize);
  return 0;
#endif

  td_publish_code(code, pageSize);
  return code;
}

void *td_make_async_witness_trampoline(uintptr_t slot, uintptr_t context) {
  size_t pageSize = 0;
  uint8_t *page = td_allocate_code_page(&pageSize);
  if (!page) {
    return 0;
  }

  TDAsyncFunctionPointer *descriptor = (TDAsyncFunctionPointer *)page;
  uint8_t *code = page + 16;
  descriptor->relativeFunction = (int32_t)(code - page);
  descriptor->expectedContextSize = TD_ASYNC_CONTEXT_SIZE;

#if defined(__aarch64__) || defined(__arm64__)
  uint32_t *cursor = (uint32_t *)code;
  td_arm64_emit_movabs(&cursor, 15, context);
  td_arm64_emit_movabs(&cursor, 16, slot);
  td_arm64_emit_movabs(&cursor, 17, (uintptr_t)&td_swift_async_trampoline_entry);
  *cursor++ = 0xd61f0220u; /* br x17 */
#elif defined(__x86_64__)
  uint8_t *cursor = code;
  td_x86_emit_movabs(&cursor, 0xbb, slot); /* movabs imm64, %r11 */
  td_x86_emit_movabs(&cursor, 0xba, context); /* movabs imm64, %r10 */
  td_x86_emit_absolute_jump(&cursor, (const void *)&td_swift_async_trampoline_entry);
#else
  munmap(page, pageSize);
  return 0;
#endif

  td_publish_code(page, pageSize);
  return descriptor;
}

void td_free_witness_trampoline(void *ptr) {
  if (!ptr) {
    return;
  }
  munmap(ptr, td_page_size());
}

const char *td_symbol_name(const void *address) {
  Dl_info info;
  if (!address || dladdr(address, &info) == 0) {
    return 0;
  }
  return info.dli_sname;
}

TDSwiftErrorAllocation td_swift_alloc_error(const void *type,
                                            const void *witnessTable,
                                            const void *flags,
                                            bool isTake) {
  return swift_allocError(type, witnessTable, flags, isTake);
}

TDMetadataResponse td_swift_get_tuple_type_metadata2(uintptr_t request,
                                                     const void *first,
                                                     const void *second,
                                                     const char *labels) {
  return swift_getTupleTypeMetadata2(request, first, second, labels, 0);
}

TDMetadataResponse td_swift_get_tuple_type_metadata3(uintptr_t request,
                                                     const void *first,
                                                     const void *second,
                                                     const void *third,
                                                     const char *labels) {
  return swift_getTupleTypeMetadata3(request, first, second, third, labels, 0);
}

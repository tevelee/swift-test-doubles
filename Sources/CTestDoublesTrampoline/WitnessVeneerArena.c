#include "TestDoublesTrampoline.h"
#include "RuntimeDescriptorLayout.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

#if !defined(MAP_ANON) && defined(MAP_ANONYMOUS)
#define MAP_ANON MAP_ANONYMOUS
#endif

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

static bool td_publish_code(void *ptr, size_t size) {
  __builtin___clear_cache((char *)ptr, (char *)ptr + size);
  return mprotect(ptr, size, PROT_READ | PROT_EXEC) == 0;
}

#define TD_VENEER_ALIGNMENT 16
#define TD_WITNESS_VENEER_CODE_CAPACITY 64
#define TD_TYPED_WITNESS_VENEER_CODE_CAPACITY 48
#define TD_ASYNC_VENEER_DESCRIPTOR_CAPACITY 16

typedef struct TDWitnessVeneerPage {
  uint8_t *mapping;
  size_t used;
  struct TDWitnessVeneerPage *next;
} TDWitnessVeneerPage;

struct TDWitnessVeneerArena {
  size_t pageSize;
  size_t pageCount;
  TDWitnessVeneerPage *firstPage;
  TDWitnessVeneerPage *lastPage;
  bool published;
  bool failed;
};

static TDWitnessVeneerPage *td_append_veneer_page(TDWitnessVeneerArena *arena) {
  size_t mappedSize = 0;
  uint8_t *mapping = td_allocate_code_page(&mappedSize);
  if (!mapping) {
    return 0;
  }

  TDWitnessVeneerPage *page = calloc(1, sizeof(TDWitnessVeneerPage));
  if (!page) {
    munmap(mapping, mappedSize);
    return 0;
  }
  page->mapping = mapping;

  if (arena->lastPage) {
    arena->lastPage->next = page;
  } else {
    arena->firstPage = page;
  }
  arena->lastPage = page;
  arena->pageSize = mappedSize;
  arena->pageCount += 1;
  return page;
}

static uint8_t *td_reserve_veneer(TDWitnessVeneerArena *arena, size_t size) {
  if (!arena || arena->published || arena->failed || size > arena->pageSize) {
    return 0;
  }

  TDWitnessVeneerPage *page = arena->lastPage;
  size_t offset = 0;
  if (page) {
    offset = (page->used + TD_VENEER_ALIGNMENT - 1) &
             ~(size_t)(TD_VENEER_ALIGNMENT - 1);
  }
  if (!page || offset > arena->pageSize || size > arena->pageSize - offset) {
    page = td_append_veneer_page(arena);
    offset = 0;
  }
  if (!page) {
    arena->failed = true;
    return 0;
  }

  uint8_t *result = page->mapping + offset;
  page->used = offset + size;
  return result;
}

#if defined(__aarch64__) || defined(__arm64__)
static uint32_t td_arm64_movz(unsigned reg, uint64_t value, unsigned halfword) {
  return 0xd2800000u | (halfword << 21) |
         ((uint32_t)(value & 0xffffu) << 5) | reg;
}

static uint32_t td_arm64_movk(unsigned reg, uint64_t value, unsigned halfword) {
  return 0xf2800000u | (halfword << 21) |
         ((uint32_t)(value & 0xffffu) << 5) | reg;
}

static void td_arm64_emit_movabs(uint32_t **cursor, unsigned reg,
                                 uintptr_t value) {
  uint64_t v = (uint64_t)value;
  *(*cursor)++ = td_arm64_movz(reg, v, 0);
  *(*cursor)++ = td_arm64_movk(reg, v >> 16, 1);
  *(*cursor)++ = td_arm64_movk(reg, v >> 32, 2);
  *(*cursor)++ = td_arm64_movk(reg, v >> 48, 3);
}
#elif defined(__x86_64__)
static void td_x86_emit_movabs(uint8_t **cursor, uint8_t opcode,
                               uintptr_t value) {
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

static bool td_emit_witness_veneer(uint8_t *code, uintptr_t slot,
                                   uintptr_t context,
                                   const void *entryTarget) {
#if defined(__aarch64__) || defined(__arm64__)
  uint32_t *cursor = (uint32_t *)code;
  td_arm64_emit_movabs(&cursor, 15, context);
  td_arm64_emit_movabs(&cursor, 16, slot);
  td_arm64_emit_movabs(&cursor, 17, (uintptr_t)entryTarget);
  *cursor++ = 0xd61f0220u; /* br x17 */
  return true;
#elif defined(__x86_64__)
  uint8_t *cursor = code;
  td_x86_emit_movabs(&cursor, 0xbb, slot); /* movabs imm64, %r11 */
  td_x86_emit_movabs(&cursor, 0xba, context); /* movabs imm64, %r10 */
  td_x86_emit_absolute_jump(&cursor, entryTarget);
  return true;
#else
  (void)code;
  (void)slot;
  (void)context;
  (void)entryTarget;
  return false;
#endif
}

static bool td_emit_read_witness_veneer(uint8_t *code, uintptr_t slot,
                                        uintptr_t context,
                                        uint16_t resumeDiscriminator,
                                        const void *entryTarget) {
#if defined(__aarch64__) || defined(__arm64__)
  uint32_t *cursor = (uint32_t *)code;
  *cursor++ = td_arm64_movz(14, resumeDiscriminator, 0);
  return td_emit_witness_veneer((uint8_t *)cursor, slot, context, entryTarget);
#else
  (void)resumeDiscriminator;
  return td_emit_witness_veneer(code, slot, context, entryTarget);
#endif
}

/// Emits a tail-call veneer for a compiler-emitted thin Swift function.
///
/// The explicit requirement arguments remain in their incoming registers. A
/// retained dispatch object is inserted as the adapter's final explicit
/// argument before branching to its native witness-compatible entry point.
static bool td_emit_typed_witness_veneer(uint8_t *code, uintptr_t invocation,
                                         uintptr_t invocationArgumentIndex,
                                         const void *entryTarget) {
#if defined(__aarch64__) || defined(__arm64__)
  if (invocationArgumentIndex >= 8) {
    return false;
  }
  uint32_t *cursor = (uint32_t *)code;
  td_arm64_emit_movabs(&cursor, (unsigned)invocationArgumentIndex, invocation);
  td_arm64_emit_movabs(&cursor, 17, (uintptr_t)entryTarget);
  *cursor++ = 0xd61f0220u; /* br x17 */
  return true;
#elif defined(__x86_64__)
  static const uint8_t prefixes[] = {0x48, 0x48, 0x48, 0x48, 0x49, 0x49};
  static const uint8_t opcodes[] = {0xbf, 0xbe, 0xba, 0xb9, 0xb8, 0xb9};
  if (invocationArgumentIndex >= 6) {
    return false;
  }
  uint8_t *cursor = code;
  *cursor++ = prefixes[invocationArgumentIndex];
  *cursor++ = opcodes[invocationArgumentIndex];
  uint64_t value = (uint64_t)invocation;
  memcpy(cursor, &value, sizeof(value));
  cursor += sizeof(value);
  td_x86_emit_absolute_jump(&cursor, entryTarget);
  return true;
#else
  (void)code;
  (void)invocation;
  (void)invocationArgumentIndex;
  (void)entryTarget;
  return false;
#endif
}

#if defined(__aarch64__) || defined(__arm64__)
_Static_assert(TD_WITNESS_VENEER_CODE_CAPACITY >= 52,
               "arm64 witness veneer capacity is too small");
_Static_assert(TD_WITNESS_VENEER_CODE_CAPACITY >= 56,
               "arm64 read witness veneer capacity is too small");
_Static_assert(TD_TYPED_WITNESS_VENEER_CODE_CAPACITY >= 36,
               "arm64 typed witness veneer capacity is too small");
#elif defined(__x86_64__)
_Static_assert(TD_WITNESS_VENEER_CODE_CAPACITY >= 34,
               "x86_64 witness veneer capacity is too small");
_Static_assert(TD_TYPED_WITNESS_VENEER_CODE_CAPACITY >= 24,
               "x86_64 typed witness veneer capacity is too small");
#endif

typedef enum TDVeneerLayout {
  TD_VENEER_LAYOUT_DIRECT,
  TD_VENEER_LAYOUT_ASYNC,
  TD_VENEER_LAYOUT_READ,
} TDVeneerLayout;

static void *td_witness_veneer_arena_make(
    TDWitnessVeneerArena *arena, uintptr_t slot, uintptr_t context,
    uint16_t resumeDiscriminator, const void *entryTarget,
    TDVeneerLayout layout) {
  size_t descriptorSize =
      layout == TD_VENEER_LAYOUT_DIRECT ? 0
                                        : TD_ASYNC_VENEER_DESCRIPTOR_CAPACITY;
  uint8_t *entry = td_reserve_veneer(
      arena, descriptorSize + TD_WITNESS_VENEER_CODE_CAPACITY);
  if (!entry) {
    return 0;
  }

  uint8_t *code = entry;
  if (layout == TD_VENEER_LAYOUT_ASYNC) {
    TDAsyncFunctionPointer *descriptor = (TDAsyncFunctionPointer *)entry;
    code = entry + TD_ASYNC_VENEER_DESCRIPTOR_CAPACITY;
    descriptor->relativeFunction = (int32_t)(code - entry);
    descriptor->expectedContextSize = TD_ASYNC_CONTEXT_SIZE;
  } else if (layout == TD_VENEER_LAYOUT_READ) {
    TDCoroFunctionPointer *descriptor = (TDCoroFunctionPointer *)entry;
    code = entry + TD_ASYNC_VENEER_DESCRIPTOR_CAPACITY;
    descriptor->relativeFunction = (int32_t)(code - entry);
    descriptor->callerFrameSize = TD_READ_CONTEXT_SIZE;
    // Swift IRGen deliberately uses zero when typed coroutine-frame malloc is
    // disabled. This veneer never requests an auxiliary allocation.
    descriptor->mallocTypeID = 0;
  }

  bool emitted =
      layout == TD_VENEER_LAYOUT_READ
          ? td_emit_read_witness_veneer(code, slot, context,
                                        resumeDiscriminator, entryTarget)
          : td_emit_witness_veneer(code, slot, context, entryTarget);
  if (!emitted) {
    arena->failed = true;
    return 0;
  }
  return entry;
}

TDWitnessVeneerArena *td_witness_veneer_arena_create(void) {
#if defined(__arm64__) && !defined(__LP64__)
  // arm64_32 can compile the package and use ManualStub, but executable
  // trampoline behavior has not been validated on physical watchOS devices.
  return 0;
#else
  TDWitnessVeneerArena *arena = calloc(1, sizeof(TDWitnessVeneerArena));
  if (arena) {
    arena->pageSize = td_page_size();
  }
  return arena;
#endif
}

void *td_witness_veneer_arena_make_witness(TDWitnessVeneerArena *arena,
                                           uintptr_t slot,
                                           uintptr_t context) {
  return td_witness_veneer_arena_make(
      arena, slot, context, 0, (const void *)&td_swift_trampoline_entry,
      TD_VENEER_LAYOUT_DIRECT);
}

void *td_witness_veneer_arena_make_async(TDWitnessVeneerArena *arena,
                                         uintptr_t slot,
                                         uintptr_t context) {
  return td_witness_veneer_arena_make(
      arena, slot, context, 0, (const void *)&td_swift_async_trampoline_entry,
      TD_VENEER_LAYOUT_ASYNC);
}

void *td_witness_veneer_arena_make_modify(TDWitnessVeneerArena *arena,
                                          uintptr_t slot,
                                          uintptr_t context) {
  return td_witness_veneer_arena_make(
      arena, slot, context, 0, (const void *)&td_swift_modify_trampoline_entry,
      TD_VENEER_LAYOUT_DIRECT);
}

void *td_witness_veneer_arena_make_read(TDWitnessVeneerArena *arena,
                                        uintptr_t slot, uintptr_t context,
                                        uint16_t resumeDiscriminator) {
  return td_witness_veneer_arena_make(
      arena, slot, context, resumeDiscriminator,
      (const void *)&td_swift_read_trampoline_entry, TD_VENEER_LAYOUT_READ);
}

void *td_witness_veneer_arena_make_typed(
    TDWitnessVeneerArena *arena, const void *target, uintptr_t invocation,
    uintptr_t invocationArgumentIndex) {
  uint8_t *entry =
      td_reserve_veneer(arena, TD_TYPED_WITNESS_VENEER_CODE_CAPACITY);
  if (!entry) {
    return 0;
  }

#if __has_feature(ptrauth_calls)
  target = ptrauth_strip(target, ptrauth_key_function_pointer);
#endif

  if (!td_emit_typed_witness_veneer(entry, invocation,
                                    invocationArgumentIndex, target)) {
    arena->failed = true;
    return 0;
  }
  return entry;
}

bool td_witness_veneer_arena_publish(TDWitnessVeneerArena *arena) {
  if (!arena || arena->published || arena->failed) {
    return false;
  }

  for (TDWitnessVeneerPage *page = arena->firstPage; page; page = page->next) {
    if (!td_publish_code(page->mapping, arena->pageSize)) {
      arena->failed = true;
      return false;
    }
  }
  arena->published = true;
  return true;
}

size_t td_witness_veneer_arena_page_count(
    const TDWitnessVeneerArena *arena) {
  return arena ? arena->pageCount : 0;
}

void td_witness_veneer_arena_destroy(TDWitnessVeneerArena *arena) {
  if (!arena) {
    return;
  }

  TDWitnessVeneerPage *page = arena->firstPage;
  while (page) {
    TDWitnessVeneerPage *next = page->next;
    munmap(page->mapping, arena->pageSize);
    free(page);
    page = next;
  }
  free(arena);
}

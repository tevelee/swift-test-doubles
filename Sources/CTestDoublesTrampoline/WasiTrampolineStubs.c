#if defined(__wasi__)

#include "TestDoublesTrampoline.h"

// TestDoublesTrampoline.S provides these symbols on arm64/x86_64. WASI has
// neither a register-based calling convention to hand-assemble against nor
// executable memory to publish a fabricated veneer into (see
// td_allocate_code_page in WitnessVeneerArena.c, which always fails there),
// so nothing here can ever run: witness veneer allocation fails first on
// every construction path that could reach these. Bodies exist only to
// satisfy the linker for code that references them unconditionally.

void td_swift_trampoline_entry(void) { __builtin_trap(); }
void td_swift_dynamic_function_entry(void) { __builtin_trap(); }
void td_swift_async_trampoline_entry(void) { __builtin_trap(); }
void td_swift_modify_trampoline_entry(void) { __builtin_trap(); }
void td_swift_modify_descriptor_trampoline_entry(void) { __builtin_trap(); }
void td_swift_read_trampoline_entry(void) { __builtin_trap(); }

void td_swift_invoke_function(
    const void *function,
    const void *context,
    uint16_t discriminator,
    TDCallFrame *frame
) {
  __builtin_trap();
}

void td_swift_invoke_witness(
    const void *function,
    const void *self,
    TDCallFrame *frame,
    uint64_t outgoingStackWord1,
    uint64_t outgoingStackWord2
) {
  __builtin_trap();
}

TDReadCoroutineResult td_swift_invoke_read_witness(
    const void *entry,
    const void *slot,
    uint16_t declarationDiscriminator,
    const void *self,
    TDCallFrame *frame,
    void *callerFrame
) {
  __builtin_trap();
}

void td_swift_resume_read_witness(
    const void *resume,
    void *callerFrame,
    uint16_t resumeDiscriminator
) {
  __builtin_trap();
}

TDModifyCoroutineResult td_swift_invoke_modify_witness(
    const void *entry,
    const void *slot,
    uint16_t declarationDiscriminator,
    const void *self,
    TDCallFrame *frame,
    void *callerFrame
) {
  __builtin_trap();
}

void td_swift_resume_modify_witness(
    const void *resume,
    void *callerFrame,
    bool isAborting
) {
  __builtin_trap();
}

// A dummy descriptor payload for td_swift_dynamic_async_function_descriptor().
// Never meaningfully dereferenced: reaching a caller that would read this
// requires a fabricated dynamic async function entry to have been installed,
// which requires the same allocation that always fails first here.
const uint32_t td_swift_dynamic_async_function_entryTu[1] = {0};

#endif // defined(__wasi__)

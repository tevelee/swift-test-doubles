#include "TestDoublesTrampoline.h"

#if defined(__APPLE__)
#define SYMBOL(name) _##name
#else
#define SYMBOL(name) name
#endif

#if defined(__aarch64__) || defined(__arm64__)

.text
.p2align 2
.globl SYMBOL(td_swift_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_trampoline_entry)
#endif
SYMBOL(td_swift_trampoline_entry):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #TD_FRAME_SIZE
    mov x9, sp

    str x16, [x9, #TD_FRAME_SLOT_OFFSET]
    str x15, [x9, #TD_FRAME_CONTEXT_OFFSET]

    stp x0, x1, [x9, #TD_FRAME_GP_OFFSET]
    stp x2, x3, [x9, #32]
    stp x4, x5, [x9, #48]
    stp x6, x7, [x9, #64]
    stp x8, x9, [x9, #80]
    stp x10, x11, [x9, #96]
    stp x12, x13, [x9, #112]
    stp x14, x15, [x9, #128]

    stp q0, q1, [x9, #TD_FRAME_FP_OFFSET]
    stp q2, q3, [x9, #176]
    stp q4, q5, [x9, #208]
    stp q6, q7, [x9, #240]
    stp q8, q9, [x9, #272]
    stp q10, q11, [x9, #304]
    stp q12, q13, [x9, #336]
    stp q14, q15, [x9, #368]

    add x10, x29, #16
    str x10, [x9, #TD_FRAME_STACK_POINTER_OFFSET]
    str x8, [x9, #TD_FRAME_INDIRECT_RESULT_OFFSET]
    str x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]
    str x21, [x9, #TD_FRAME_SWIFT_ERROR_OFFSET]
    str xzr, [x9, #TD_FRAME_RESERVED_OFFSET]
    str x21, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]

    mov x0, x9
    bl SYMBOL(td_swift_trampoline_handler)

    mov x9, sp
    ldr x0, [x9, #TD_FRAME_RETURN_GP_OFFSET]
    ldr x1, [x9, #448]
    ldr x2, [x9, #456]
    ldr x3, [x9, #464]
    ldr d0, [x9, #TD_FRAME_RETURN_FP_OFFSET]
    ldr d1, [x9, #480]
    ldr d2, [x9, #488]
    ldr d3, [x9, #496]
    ldr x21, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
    ldr x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]

    add sp, sp, #TD_FRAME_SIZE
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl SYMBOL(td_swift_dynamic_function_entry)
SYMBOL(td_swift_dynamic_function_entry):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #TD_FRAME_SIZE
    mov x9, sp

    stp x0, x1, [x9, #TD_FRAME_GP_OFFSET]
    stp x2, x3, [x9, #32]
    stp x4, x5, [x9, #48]
    stp x6, x7, [x9, #64]
    stp x8, x9, [x9, #80]
    stp x10, x11, [x9, #96]
    stp x12, x13, [x9, #112]
    stp x14, x15, [x9, #128]

    stp q0, q1, [x9, #TD_FRAME_FP_OFFSET]
    stp q2, q3, [x9, #176]
    stp q4, q5, [x9, #208]
    stp q6, q7, [x9, #240]
    stp q8, q9, [x9, #272]
    stp q10, q11, [x9, #304]
    stp q12, q13, [x9, #336]
    stp q14, q15, [x9, #368]

    add x10, x29, #16
    str x10, [x9, #TD_FRAME_STACK_POINTER_OFFSET]
    str x8, [x9, #TD_FRAME_INDIRECT_RESULT_OFFSET]
    str x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]
    str x21, [x9, #TD_FRAME_SWIFT_ERROR_OFFSET]
    // x21 is callee-saved for nonthrowing Swift functions. Preserve it unless
    // the metadata-aware handler explicitly publishes a throwing result.
    str x21, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]

    mov x0, x9
    bl SYMBOL(td_swift_dynamic_function_handler)

    mov x9, sp
    ldr x0, [x9, #TD_FRAME_RETURN_GP_OFFSET]
    ldr x1, [x9, #448]
    ldr x2, [x9, #456]
    ldr x3, [x9, #464]
    ldr d0, [x9, #TD_FRAME_RETURN_FP_OFFSET]
    ldr d1, [x9, #480]
    ldr d2, [x9, #488]
    ldr d3, [x9, #496]
    ldr x21, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
    ldr x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]

    add sp, sp, #TD_FRAME_SIZE
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl SYMBOL(td_swift_invoke_function)
SYMBOL(td_swift_invoke_function):
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    mov x16, x0
    mov x20, x1
    mov x17, x2
    mov x19, x3
    ldr x8, [x19, #TD_FRAME_INDIRECT_RESULT_OFFSET]
    ldp q0, q1, [x19, #TD_FRAME_FP_OFFSET]
    ldp q2, q3, [x19, #176]
    ldp q4, q5, [x19, #208]
    ldp q6, q7, [x19, #240]
    ldp x0, x1, [x19, #TD_FRAME_GP_OFFSET]
    ldp x2, x3, [x19, #32]
    ldp x4, x5, [x19, #48]
    ldp x6, x7, [x19, #64]
    mov x21, #0
#if defined(__arm64e__)
    blraa x16, x17
#else
    blr x16
#endif
    stp x0, x1, [x19, #TD_FRAME_RETURN_GP_OFFSET]
    stp x2, x3, [x19, #456]
    str d0, [x19, #TD_FRAME_RETURN_FP_OFFSET]
    str d1, [x19, #480]
    str d2, [x19, #488]
    str d3, [x19, #496]
    str x21, [x19, #TD_FRAME_RETURN_ERROR_OFFSET]
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.p2align 2
.globl SYMBOL(td_swift_invoke_async_function)
SYMBOL(td_swift_invoke_async_function):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    str x3, [x22, #16]
    str x1, [x22, #32]
    str x2, [x22, #40]
    strb w4, [x22, #48]

    mov x16, x0
#if defined(__arm64e__)
    mov x17, x2
    autda x16, x17
#endif
    ldrsw x17, [x16]
    add x17, x16, x17
#if defined(__arm64e__)
    pacia x17, x2
#endif
    str x17, [x22, #24]
    ldr w0, [x16, #4]
    bl SYMBOL(swift_task_alloc)

    mov x11, x22
#if defined(__APPLE__)
    adrp x8, SYMBOL(td_swift_invoke_async_function_complete)@PAGE
    add x8, x8, SYMBOL(td_swift_invoke_async_function_complete)@PAGEOFF
#else
    adrp x8, SYMBOL(td_swift_invoke_async_function_complete)
    add x8, x8, :lo12:SYMBOL(td_swift_invoke_async_function_complete)
#endif
    stp x11, x8, [x0]
    mov x10, x0
    ldr x9, [x11, #16]
    ldr x17, [x11, #24]
    ldr x20, [x11, #32]
    ldr x16, [x11, #40]

    ldp q0, q1, [x9, #TD_FRAME_FP_OFFSET]
    ldp q2, q3, [x9, #176]
    ldp q4, q5, [x9, #208]
    ldp q6, q7, [x9, #240]
    ldp x0, x1, [x9, #TD_FRAME_GP_OFFSET]
    ldp x2, x3, [x9, #32]
    ldp x4, x5, [x9, #48]
    ldp x6, x7, [x9, #64]
    mov x22, x10

    ldp x29, x30, [sp], #16
#if defined(__arm64e__)
    braa x17, x16
#else
    br x17
#endif

.p2align 2
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_invoke_async_function_complete)
#endif
SYMBOL(td_swift_invoke_async_function_complete):
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    ldr x8, [x22]
    ldr x9, [x8, #16]
    stp x0, x1, [x9, #TD_FRAME_RETURN_GP_OFFSET]
    stp x2, x3, [x9, #456]
    str d0, [x9, #TD_FRAME_RETURN_FP_OFFSET]
    str d1, [x9, #480]
    str d2, [x9, #488]
    str d3, [x9, #496]
    ldrb w10, [x8, #48]
    cbz w10, .Ltd_async_invoke_nonthrowing_arm64
    str x20, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
    b .Ltd_async_invoke_error_stored_arm64
.Ltd_async_invoke_nonthrowing_arm64:
    str xzr, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
.Ltd_async_invoke_error_stored_arm64:
    stp x8, x9, [sp, #16]

    mov x0, x22
    bl SYMBOL(swift_task_dealloc)

    ldr x22, [sp, #16]
    ldr x16, [x22, #8]
    mov x20, #0
    ldp x29, x30, [sp], #32
    br x16

.p2align 2
.globl SYMBOL(td_swift_dynamic_async_function_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_dynamic_async_function_entry)
#endif
SYMBOL(td_swift_dynamic_async_function_entry):
    mov x15, x20
    mov x16, #-1
    lsr x16, x16, #1
    b SYMBOL(td_swift_async_trampoline_entry)

.p2align 2
.globl SYMBOL(td_swift_async_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_async_trampoline_entry)
#endif
SYMBOL(td_swift_async_trampoline_entry):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #TD_FRAME_SIZE
    mov x9, sp

    str x16, [x9, #TD_FRAME_SLOT_OFFSET]
    str x15, [x9, #TD_FRAME_CONTEXT_OFFSET]

    stp x0, x1, [x9, #TD_FRAME_GP_OFFSET]
    stp x2, x3, [x9, #32]
    stp x4, x5, [x9, #48]
    stp x6, x7, [x9, #64]
    stp x8, x9, [x9, #80]
    stp x10, x11, [x9, #96]
    stp x12, x13, [x9, #112]
    stp x14, x15, [x9, #128]

    stp q0, q1, [x9, #TD_FRAME_FP_OFFSET]
    stp q2, q3, [x9, #176]
    stp q4, q5, [x9, #208]
    stp q6, q7, [x9, #240]
    stp q8, q9, [x9, #272]
    stp q10, q11, [x9, #304]
    stp q12, q13, [x9, #336]
    stp q14, q15, [x9, #368]

    add x10, x29, #16
    str x10, [x9, #TD_FRAME_STACK_POINTER_OFFSET]
    str x0, [x9, #TD_FRAME_INDIRECT_RESULT_OFFSET]
    str x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]
    str xzr, [x9, #TD_FRAME_SWIFT_ERROR_OFFSET]
    str x22, [x9, #TD_FRAME_RESERVED_OFFSET]
    str xzr, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]

    mov x0, x9
    bl SYMBOL(td_swift_async_trampoline_handler)

    cbz x0, .Ltd_async_immediate_arm64
    str x0, [x22, #TD_ASYNC_CONTEXT_STATE_OFFSET]

#if defined(__APPLE__)
    adrp x8, SYMBOL(td_swift_async_dispatchTu)@PAGE
    add x8, x8, SYMBOL(td_swift_async_dispatchTu)@PAGEOFF
#else
    adrp x8, SYMBOL(td_swift_async_dispatchTu)
    add x8, x8, :lo12:SYMBOL(td_swift_async_dispatchTu)
#endif
    ldrsw x10, [x8]
    add x10, x8, x10
    str x10, [sp, #TD_FRAME_RETURN_GP_OFFSET]
    ldr w0, [x8, #4]
    bl SYMBOL(swift_task_alloc)

    str x0, [x22, #TD_ASYNC_CONTEXT_CALLEE_OFFSET]
#if defined(__APPLE__)
    adrp x8, SYMBOL(td_swift_async_trampoline_complete)@PAGE
    add x8, x8, SYMBOL(td_swift_async_trampoline_complete)@PAGEOFF
#else
    adrp x8, SYMBOL(td_swift_async_trampoline_complete)
    add x8, x8, :lo12:SYMBOL(td_swift_async_trampoline_complete)
#endif
    stp x22, x8, [x0]
    ldr x1, [x22, #TD_ASYNC_CONTEXT_STATE_OFFSET]
    mov x22, x0
    mov x0, x1
    ldr x17, [sp, #TD_FRAME_RETURN_GP_OFFSET]

    add sp, sp, #TD_FRAME_SIZE
    ldp x29, x30, [sp], #16
    br x17

.Ltd_async_immediate_arm64:
    mov x9, sp
    ldr x0, [x9, #TD_FRAME_RETURN_GP_OFFSET]
    ldr x1, [x9, #448]
    ldr x2, [x9, #456]
    ldr x3, [x9, #464]
    ldr d0, [x9, #TD_FRAME_RETURN_FP_OFFSET]
    ldr d1, [x9, #480]
    ldr d2, [x9, #488]
    ldr d3, [x9, #496]
    ldr x20, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
    ldr x22, [x9, #TD_FRAME_RESERVED_OFFSET]
    ldr x16, [x22, #8]

    add sp, sp, #TD_FRAME_SIZE
    ldp x29, x30, [sp], #16
    br x16

.p2align 2
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_async_trampoline_complete)
#endif
SYMBOL(td_swift_async_trampoline_complete):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #TD_ASYNC_COMPLETION_FRAME_SIZE

    ldr x8, [x22]
    str x8, [sp, #TD_ASYNC_COMPLETION_PARENT_OFFSET]
    ldr x9, [x8, #TD_ASYNC_CONTEXT_STATE_OFFSET]
    str x9, [sp, #TD_ASYNC_COMPLETION_STATE_OFFSET]

    mov x0, x22
    bl SYMBOL(swift_task_dealloc)

    ldr x0, [sp, #TD_ASYNC_COMPLETION_STATE_OFFSET]
    mov x1, sp
    bl SYMBOL(td_swift_async_dispatch_finish)

    mov x9, sp
    ldr x0, [x9, #TD_FRAME_RETURN_GP_OFFSET]
    ldr x1, [x9, #448]
    ldr x2, [x9, #456]
    ldr x3, [x9, #464]
    ldr d0, [x9, #TD_FRAME_RETURN_FP_OFFSET]
    ldr d1, [x9, #480]
    ldr d2, [x9, #488]
    ldr d3, [x9, #496]
    ldr x20, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]
    ldr x22, [x9, #TD_ASYNC_COMPLETION_PARENT_OFFSET]
    ldr x16, [x22, #8]

    add sp, sp, #TD_ASYNC_COMPLETION_FRAME_SIZE
    ldp x29, x30, [sp], #16
    br x16

.p2align 2
.globl SYMBOL(td_swift_modify_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_modify_trampoline_entry)
#endif
SYMBOL(td_swift_modify_trampoline_entry):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #TD_FRAME_SIZE
    mov x9, sp

    str x16, [x9, #TD_FRAME_SLOT_OFFSET]
    str x15, [x9, #TD_FRAME_CONTEXT_OFFSET]

    stp x0, x1, [x9, #TD_FRAME_GP_OFFSET]
    stp x2, x3, [x9, #32]
    stp x4, x5, [x9, #48]
    stp x6, x7, [x9, #64]
    stp x8, x9, [x9, #80]
    stp x10, x11, [x9, #96]
    stp x12, x13, [x9, #112]
    stp x14, x15, [x9, #128]

    stp q0, q1, [x9, #TD_FRAME_FP_OFFSET]
    stp q2, q3, [x9, #176]
    stp q4, q5, [x9, #208]
    stp q6, q7, [x9, #240]
    stp q8, q9, [x9, #272]
    stp q10, q11, [x9, #304]
    stp q12, q13, [x9, #336]
    stp q14, q15, [x9, #368]

    add x10, x29, #16
    str x10, [x9, #TD_FRAME_STACK_POINTER_OFFSET]
    str x8, [x9, #TD_FRAME_INDIRECT_RESULT_OFFSET]
    str x20, [x9, #TD_FRAME_SWIFT_SELF_OFFSET]
    str xzr, [x9, #TD_FRAME_SWIFT_ERROR_OFFSET]
    str xzr, [x9, #TD_FRAME_RESERVED_OFFSET]
    str xzr, [x9, #TD_FRAME_RETURN_ERROR_OFFSET]

    mov x0, x9
    bl SYMBOL(td_swift_modify_trampoline_handler)

    ldr x9, [sp, #TD_FRAME_GP_OFFSET]
    str x0, [x9, #TD_MODIFY_CONTEXT_STATE_OFFSET]
    mov x8, x1
#if defined(__APPLE__)
    adrp x16, SYMBOL(td_swift_modify_trampoline_resume)@PAGE
    add x16, x16, SYMBOL(td_swift_modify_trampoline_resume)@PAGEOFF
#else
    adrp x16, SYMBOL(td_swift_modify_trampoline_resume)
    add x16, x16, :lo12:SYMBOL(td_swift_modify_trampoline_resume)
#endif
#if defined(__arm64e__)
    mov x17, x9
    movk x17, #TD_MODIFY_RESUME_DISCRIMINATOR, lsl #48
    pacia x16, x17
#endif
    mov x0, x16
    mov x1, x8

    add sp, sp, #TD_FRAME_SIZE
    ldp x29, x30, [sp], #16
    ret

.p2align 2
.globl SYMBOL(td_swift_modify_trampoline_resume)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_modify_trampoline_resume)
#endif
SYMBOL(td_swift_modify_trampoline_resume):
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x8, [x0, #TD_MODIFY_CONTEXT_STATE_OFFSET]
    str xzr, [x0, #TD_MODIFY_CONTEXT_STATE_OFFSET]
    mov x0, x8
    bl SYMBOL(td_swift_modify_trampoline_resume_handler)
    ldp x29, x30, [sp], #16
    ret

#elif defined(__x86_64__)

.text
.globl SYMBOL(td_swift_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_trampoline_entry)
#endif
SYMBOL(td_swift_trampoline_entry):
    pushq %rbp
    movq %rsp, %rbp
    subq $TD_FRAME_SIZE, %rsp
    movq %rax, TD_FRAME_INDIRECT_RESULT_OFFSET(%rsp)
    movq %rsp, %rax

    movq %r11, TD_FRAME_SLOT_OFFSET(%rax)
    movq %r10, TD_FRAME_CONTEXT_OFFSET(%rax)

    movq %rdi, TD_FRAME_GP_OFFSET(%rax)
    movq %rsi, 24(%rax)
    movq %rdx, 32(%rax)
    movq %rcx, 40(%rax)
    movq %r8, 48(%rax)
    movq %r9, 56(%rax)
    movq %r10, 64(%rax)
    movq %r11, 72(%rax)
    movq %r12, 80(%rax)
    movq %r13, 88(%rax)
    movq %r14, 96(%rax)
    movq %r15, 104(%rax)
    movq %rax, 112(%rax)
    movq %rbx, 120(%rax)
    movq %rbp, 128(%rax)
    movq %rsp, 136(%rax)

    movdqu %xmm0, TD_FRAME_FP_OFFSET(%rax)
    movdqu %xmm1, 160(%rax)
    movdqu %xmm2, 176(%rax)
    movdqu %xmm3, 192(%rax)
    movdqu %xmm4, 208(%rax)
    movdqu %xmm5, 224(%rax)
    movdqu %xmm6, 240(%rax)
    movdqu %xmm7, 256(%rax)
    movdqu %xmm8, 272(%rax)
    movdqu %xmm9, 288(%rax)
    movdqu %xmm10, 304(%rax)
    movdqu %xmm11, 320(%rax)
    movdqu %xmm12, 336(%rax)
    movdqu %xmm13, 352(%rax)
    movdqu %xmm14, 368(%rax)
    movdqu %xmm15, 384(%rax)

    leaq 16(%rbp), %rcx
    movq %rcx, TD_FRAME_STACK_POINTER_OFFSET(%rax)
    movq %r13, TD_FRAME_SWIFT_SELF_OFFSET(%rax)
    movq %r12, TD_FRAME_SWIFT_ERROR_OFFSET(%rax)
    movq $0, TD_FRAME_RESERVED_OFFSET(%rax)
    movq %r12, TD_FRAME_RETURN_ERROR_OFFSET(%rax)

    movq %rax, %rdi
    callq SYMBOL(td_swift_trampoline_handler)

    movq %rsp, %r10
    movq TD_FRAME_RETURN_GP_OFFSET(%r10), %rax
    movq 448(%r10), %rdx
    movq 456(%r10), %rcx
    movq 464(%r10), %r8
    movsd TD_FRAME_RETURN_FP_OFFSET(%r10), %xmm0
    movsd 480(%r10), %xmm1
    movsd 488(%r10), %xmm2
    movsd 496(%r10), %xmm3
    movq TD_FRAME_RETURN_ERROR_OFFSET(%r10), %r12
    movq TD_FRAME_SWIFT_SELF_OFFSET(%r10), %r13

    leave
    retq

.globl SYMBOL(td_swift_dynamic_function_entry)
SYMBOL(td_swift_dynamic_function_entry):
    pushq %rbp
    movq %rsp, %rbp
    subq $TD_FRAME_SIZE, %rsp
    movq %rax, TD_FRAME_INDIRECT_RESULT_OFFSET(%rsp)
    movq %rsp, %rax

    movq %rdi, TD_FRAME_GP_OFFSET(%rax)
    movq %rsi, 24(%rax)
    movq %rdx, 32(%rax)
    movq %rcx, 40(%rax)
    movq %r8, 48(%rax)
    movq %r9, 56(%rax)
    movq %r10, 64(%rax)
    movq %r11, 72(%rax)
    movq %r12, 80(%rax)
    movq %r13, 88(%rax)
    movq %r14, 96(%rax)
    movq %r15, 104(%rax)
    movq %rax, 112(%rax)
    movq %rbx, 120(%rax)
    movq %rbp, 128(%rax)
    movq %rsp, 136(%rax)

    movdqu %xmm0, TD_FRAME_FP_OFFSET(%rax)
    movdqu %xmm1, 160(%rax)
    movdqu %xmm2, 176(%rax)
    movdqu %xmm3, 192(%rax)
    movdqu %xmm4, 208(%rax)
    movdqu %xmm5, 224(%rax)
    movdqu %xmm6, 240(%rax)
    movdqu %xmm7, 256(%rax)
    movdqu %xmm8, 272(%rax)
    movdqu %xmm9, 288(%rax)
    movdqu %xmm10, 304(%rax)
    movdqu %xmm11, 320(%rax)
    movdqu %xmm12, 336(%rax)
    movdqu %xmm13, 352(%rax)
    movdqu %xmm14, 368(%rax)
    movdqu %xmm15, 384(%rax)

    leaq 16(%rbp), %rcx
    movq %rcx, TD_FRAME_STACK_POINTER_OFFSET(%rax)
    movq %r13, TD_FRAME_SWIFT_SELF_OFFSET(%rax)
    movq %r12, TD_FRAME_SWIFT_ERROR_OFFSET(%rax)
    // r12 is callee-saved for nonthrowing Swift functions. Preserve it unless
    // the metadata-aware handler explicitly publishes a throwing result.
    movq %r12, TD_FRAME_RETURN_ERROR_OFFSET(%rax)

    movq %rax, %rdi
    callq SYMBOL(td_swift_dynamic_function_handler)

    movq %rsp, %r10
    movq TD_FRAME_RETURN_GP_OFFSET(%r10), %rax
    movq 448(%r10), %rdx
    movq 456(%r10), %rcx
    movq 464(%r10), %r8
    movsd TD_FRAME_RETURN_FP_OFFSET(%r10), %xmm0
    movsd 480(%r10), %xmm1
    movsd 488(%r10), %xmm2
    movsd 496(%r10), %xmm3
    movq TD_FRAME_RETURN_ERROR_OFFSET(%r10), %r12
    movq TD_FRAME_SWIFT_SELF_OFFSET(%r10), %r13

    leave
    retq

.globl SYMBOL(td_swift_invoke_function)
SYMBOL(td_swift_invoke_function):
    pushq %rbp
    movq %rsp, %rbp
    pushq %rbx
    pushq %r13
    pushq %r12
    subq $8, %rsp
    movq %rcx, %rbx
    movq %rsi, %r13
    movq %rdi, %r11
    movq TD_FRAME_INDIRECT_RESULT_OFFSET(%rbx), %rax
    movsd TD_FRAME_FP_OFFSET(%rbx), %xmm0
    movsd 160(%rbx), %xmm1
    movsd 176(%rbx), %xmm2
    movsd 192(%rbx), %xmm3
    movsd 208(%rbx), %xmm4
    movsd 224(%rbx), %xmm5
    movsd 240(%rbx), %xmm6
    movsd 256(%rbx), %xmm7
    movq TD_FRAME_GP_OFFSET(%rbx), %rdi
    movq 24(%rbx), %rsi
    movq 32(%rbx), %rdx
    movq 40(%rbx), %rcx
    movq 48(%rbx), %r8
    movq 56(%rbx), %r9
    xorq %r12, %r12
    callq *%r11
    movq %rax, TD_FRAME_RETURN_GP_OFFSET(%rbx)
    movq %rdx, 448(%rbx)
    movq %rcx, 456(%rbx)
    movq %r8, 464(%rbx)
    movsd %xmm0, TD_FRAME_RETURN_FP_OFFSET(%rbx)
    movsd %xmm1, 480(%rbx)
    movsd %xmm2, 488(%rbx)
    movsd %xmm3, 496(%rbx)
    movq %r12, TD_FRAME_RETURN_ERROR_OFFSET(%rbx)
    addq $8, %rsp
    popq %r12
    popq %r13
    popq %rbx
    popq %rbp
    retq

.globl SYMBOL(td_swift_invoke_async_function)
SYMBOL(td_swift_invoke_async_function):
    pushq %rbp
    movq %rsp, %rbp
    movq %rcx, 16(%r14)
    movq %rsi, 32(%r14)
    movb %r8b, 48(%r14)

    movslq (%rdi), %rax
    addq %rdi, %rax
    movq %rax, 24(%r14)
    movl 4(%rdi), %edi
    callq SYMBOL(swift_task_alloc)

    movq %r14, (%rax)
    leaq SYMBOL(td_swift_invoke_async_function_complete)(%rip), %rcx
    movq %rcx, 8(%rax)
    movq 16(%r14), %r10
    movq 24(%r14), %r11
    movq 32(%r14), %r13
    movq %rax, %r14

    movsd TD_FRAME_FP_OFFSET(%r10), %xmm0
    movsd 160(%r10), %xmm1
    movsd 176(%r10), %xmm2
    movsd 192(%r10), %xmm3
    movsd 208(%r10), %xmm4
    movsd 224(%r10), %xmm5
    movsd 240(%r10), %xmm6
    movsd 256(%r10), %xmm7
    movq TD_FRAME_GP_OFFSET(%r10), %rdi
    movq 24(%r10), %rsi
    movq 32(%r10), %rdx
    movq 40(%r10), %rcx
    movq 48(%r10), %r8
    movq 56(%r10), %r9

    popq %rbp
    jmpq *%r11

#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_invoke_async_function_complete)
#endif
SYMBOL(td_swift_invoke_async_function_complete):
    pushq %rbp
    movq %rsp, %rbp
    subq $16, %rsp
    movq (%r14), %rax
    movq 16(%rax), %r10
    movq %rdi, TD_FRAME_RETURN_GP_OFFSET(%r10)
    movq %rsi, 448(%r10)
    movq %rdx, 456(%r10)
    movq %rcx, 464(%r10)
    movsd %xmm0, TD_FRAME_RETURN_FP_OFFSET(%r10)
    movsd %xmm1, 480(%r10)
    movsd %xmm2, 488(%r10)
    movsd %xmm3, 496(%r10)
    cmpb $0, 48(%rax)
    je .Ltd_async_invoke_nonthrowing_x86_64
    movq %r13, TD_FRAME_RETURN_ERROR_OFFSET(%r10)
    jmp .Ltd_async_invoke_error_stored_x86_64
.Ltd_async_invoke_nonthrowing_x86_64:
    movq $0, TD_FRAME_RETURN_ERROR_OFFSET(%r10)
.Ltd_async_invoke_error_stored_x86_64:
    movq %rax, -8(%rbp)

    movq %r14, %rdi
    callq SYMBOL(swift_task_dealloc)

    movq -8(%rbp), %r14
    movq 8(%r14), %r11
    xorq %r13, %r13
    leave
    jmpq *%r11

.globl SYMBOL(td_swift_dynamic_async_function_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_dynamic_async_function_entry)
#endif
SYMBOL(td_swift_dynamic_async_function_entry):
    movq %r13, %r10
    movabsq $0x7fffffffffffffff, %r11
    jmp SYMBOL(td_swift_async_trampoline_entry)

.globl SYMBOL(td_swift_async_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_async_trampoline_entry)
#endif
SYMBOL(td_swift_async_trampoline_entry):
    pushq %rbp
    movq %rsp, %rbp
    subq $TD_FRAME_SIZE, %rsp
    movq %rsp, %rax

    movq %r11, TD_FRAME_SLOT_OFFSET(%rax)
    movq %r10, TD_FRAME_CONTEXT_OFFSET(%rax)

    movq %rdi, TD_FRAME_GP_OFFSET(%rax)
    movq %rsi, 24(%rax)
    movq %rdx, 32(%rax)
    movq %rcx, 40(%rax)
    movq %r8, 48(%rax)
    movq %r9, 56(%rax)
    movq %r10, 64(%rax)
    movq %r11, 72(%rax)
    movq %r12, 80(%rax)
    movq %r13, 88(%rax)
    movq %r14, 96(%rax)
    movq %r15, 104(%rax)
    movq %rax, 112(%rax)
    movq %rbx, 120(%rax)
    movq %rbp, 128(%rax)
    movq %rsp, 136(%rax)

    movdqu %xmm0, TD_FRAME_FP_OFFSET(%rax)
    movdqu %xmm1, 160(%rax)
    movdqu %xmm2, 176(%rax)
    movdqu %xmm3, 192(%rax)
    movdqu %xmm4, 208(%rax)
    movdqu %xmm5, 224(%rax)
    movdqu %xmm6, 240(%rax)
    movdqu %xmm7, 256(%rax)
    movdqu %xmm8, 272(%rax)
    movdqu %xmm9, 288(%rax)
    movdqu %xmm10, 304(%rax)
    movdqu %xmm11, 320(%rax)
    movdqu %xmm12, 336(%rax)
    movdqu %xmm13, 352(%rax)
    movdqu %xmm14, 368(%rax)
    movdqu %xmm15, 384(%rax)

    leaq 16(%rbp), %rcx
    movq %rcx, TD_FRAME_STACK_POINTER_OFFSET(%rax)
    movq %rdi, TD_FRAME_INDIRECT_RESULT_OFFSET(%rax)
    movq %r13, TD_FRAME_SWIFT_SELF_OFFSET(%rax)
    movq $0, TD_FRAME_SWIFT_ERROR_OFFSET(%rax)
    movq %r14, TD_FRAME_RESERVED_OFFSET(%rax)
    movq $0, TD_FRAME_RETURN_ERROR_OFFSET(%rax)

    movq %rax, %rdi
    callq SYMBOL(td_swift_async_trampoline_handler)

    testq %rax, %rax
    je .Ltd_async_immediate_x86_64
    movq %rax, TD_ASYNC_CONTEXT_STATE_OFFSET(%r14)

    leaq SYMBOL(td_swift_async_dispatchTu)(%rip), %rcx
    movslq (%rcx), %rdx
    addq %rcx, %rdx
    movq %rdx, TD_FRAME_RETURN_GP_OFFSET(%rsp)
    movl 4(%rcx), %edi
    callq SYMBOL(swift_task_alloc)

    movq %rax, TD_ASYNC_CONTEXT_CALLEE_OFFSET(%r14)
    leaq SYMBOL(td_swift_async_trampoline_complete)(%rip), %rcx
    movq %r14, (%rax)
    movq %rcx, 8(%rax)
    movq TD_ASYNC_CONTEXT_STATE_OFFSET(%r14), %rdi
    movq %rax, %r14
    movq TD_FRAME_RETURN_GP_OFFSET(%rsp), %r11

    leave
    jmpq *%r11

.Ltd_async_immediate_x86_64:
    movq %rsp, %r10
    movq TD_FRAME_RETURN_GP_OFFSET(%r10), %rdi
    movq 448(%r10), %rsi
    movq 456(%r10), %rdx
    movq 464(%r10), %rcx
    movsd TD_FRAME_RETURN_FP_OFFSET(%r10), %xmm0
    movsd 480(%r10), %xmm1
    movsd 488(%r10), %xmm2
    movsd 496(%r10), %xmm3
    movq TD_FRAME_RETURN_ERROR_OFFSET(%r10), %r13
    movq TD_FRAME_RESERVED_OFFSET(%r10), %r14
    movq 8(%r14), %r11

    leave
    jmpq *%r11

#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_async_trampoline_complete)
#endif
SYMBOL(td_swift_async_trampoline_complete):
    pushq %rbp
    movq %rsp, %rbp
    subq $TD_ASYNC_COMPLETION_FRAME_SIZE, %rsp

    movq (%r14), %rax
    movq %rax, TD_ASYNC_COMPLETION_PARENT_OFFSET(%rsp)
    movq TD_ASYNC_CONTEXT_STATE_OFFSET(%rax), %rcx
    movq %rcx, TD_ASYNC_COMPLETION_STATE_OFFSET(%rsp)

    movq %r14, %rdi
    callq SYMBOL(swift_task_dealloc)

    movq TD_ASYNC_COMPLETION_STATE_OFFSET(%rsp), %rdi
    movq %rsp, %rsi
    callq SYMBOL(td_swift_async_dispatch_finish)

    movq %rsp, %r10
    movq TD_FRAME_RETURN_GP_OFFSET(%r10), %rdi
    movq 448(%r10), %rsi
    movq 456(%r10), %rdx
    movq 464(%r10), %rcx
    movsd TD_FRAME_RETURN_FP_OFFSET(%r10), %xmm0
    movsd 480(%r10), %xmm1
    movsd 488(%r10), %xmm2
    movsd 496(%r10), %xmm3
    movq TD_FRAME_RETURN_ERROR_OFFSET(%r10), %r13
    movq TD_ASYNC_COMPLETION_PARENT_OFFSET(%r10), %r14
    movq 8(%r14), %r11

    leave
    jmpq *%r11

.globl SYMBOL(td_swift_modify_trampoline_entry)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_modify_trampoline_entry)
#endif
SYMBOL(td_swift_modify_trampoline_entry):
    pushq %rbp
    movq %rsp, %rbp
    subq $TD_FRAME_SIZE, %rsp
    movq %rax, TD_FRAME_INDIRECT_RESULT_OFFSET(%rsp)
    movq %rsp, %rax

    movq %r11, TD_FRAME_SLOT_OFFSET(%rax)
    movq %r10, TD_FRAME_CONTEXT_OFFSET(%rax)

    movq %rdi, TD_FRAME_GP_OFFSET(%rax)
    movq %rsi, 24(%rax)
    movq %rdx, 32(%rax)
    movq %rcx, 40(%rax)
    movq %r8, 48(%rax)
    movq %r9, 56(%rax)
    movq %r10, 64(%rax)
    movq %r11, 72(%rax)
    movq %r12, 80(%rax)
    movq %r13, 88(%rax)
    movq %r14, 96(%rax)
    movq %r15, 104(%rax)
    movq %rax, 112(%rax)
    movq %rbx, 120(%rax)
    movq %rbp, 128(%rax)
    movq %rsp, 136(%rax)

    movdqu %xmm0, TD_FRAME_FP_OFFSET(%rax)
    movdqu %xmm1, 160(%rax)
    movdqu %xmm2, 176(%rax)
    movdqu %xmm3, 192(%rax)
    movdqu %xmm4, 208(%rax)
    movdqu %xmm5, 224(%rax)
    movdqu %xmm6, 240(%rax)
    movdqu %xmm7, 256(%rax)
    movdqu %xmm8, 272(%rax)
    movdqu %xmm9, 288(%rax)
    movdqu %xmm10, 304(%rax)
    movdqu %xmm11, 320(%rax)
    movdqu %xmm12, 336(%rax)
    movdqu %xmm13, 352(%rax)
    movdqu %xmm14, 368(%rax)
    movdqu %xmm15, 384(%rax)

    leaq 16(%rbp), %rcx
    movq %rcx, TD_FRAME_STACK_POINTER_OFFSET(%rax)
    movq %r13, TD_FRAME_SWIFT_SELF_OFFSET(%rax)
    movq $0, TD_FRAME_SWIFT_ERROR_OFFSET(%rax)
    movq $0, TD_FRAME_RESERVED_OFFSET(%rax)
    movq $0, TD_FRAME_RETURN_ERROR_OFFSET(%rax)

    movq %rax, %rdi
    callq SYMBOL(td_swift_modify_trampoline_handler)

    movq TD_FRAME_GP_OFFSET(%rsp), %rcx
    movq %rax, TD_MODIFY_CONTEXT_STATE_OFFSET(%rcx)
    leaq SYMBOL(td_swift_modify_trampoline_resume)(%rip), %rax

    leave
    retq

.globl SYMBOL(td_swift_modify_trampoline_resume)
#if defined(__APPLE__)
.private_extern SYMBOL(td_swift_modify_trampoline_resume)
#endif
SYMBOL(td_swift_modify_trampoline_resume):
    pushq %rbp
    movq %rsp, %rbp
    movq TD_MODIFY_CONTEXT_STATE_OFFSET(%rdi), %rax
    movq $0, TD_MODIFY_CONTEXT_STATE_OFFSET(%rdi)
    movq %rax, %rdi
    callq SYMBOL(td_swift_modify_trampoline_resume_handler)
    popq %rbp
    retq

#endif

#if defined(__APPLE__)
.section __TEXT,__const
#else
.section .rodata
#endif
.p2align 3
.globl SYMBOL(td_swift_invoke_async_functionTu)
SYMBOL(td_swift_invoke_async_functionTu):
    .long SYMBOL(td_swift_invoke_async_function) - SYMBOL(td_swift_invoke_async_functionTu)
    .long 64

.p2align 3
.globl SYMBOL(td_swift_dynamic_async_function_entryTu)
SYMBOL(td_swift_dynamic_async_function_entryTu):
    .long SYMBOL(td_swift_dynamic_async_function_entry) - SYMBOL(td_swift_dynamic_async_function_entryTu)
    .long TD_ASYNC_CONTEXT_SIZE

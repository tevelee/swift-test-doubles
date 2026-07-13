#include "TestDoublesTrampoline.h"

#if defined(__APPLE__)
#define SYMBOL(name) _##name
#else
#define SYMBOL(name) name
#endif

#if defined(__aarch64__) || defined(__arm64__)

.text
.align 2
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

.align 2
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

.align 2
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

#endif

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
    sub sp, sp, #1024
    mov x9, sp

    str x16, [x9, #0]

    stp x0, x1, [x9, #16]
    stp x2, x3, [x9, #32]
    stp x4, x5, [x9, #48]
    stp x6, x7, [x9, #64]
    stp x8, x9, [x9, #80]
    stp x10, x11, [x9, #96]
    stp x12, x13, [x9, #112]
    stp x14, x15, [x9, #128]

    stp q0, q1, [x9, #144]
    stp q2, q3, [x9, #176]
    stp q4, q5, [x9, #208]
    stp q6, q7, [x9, #240]
    stp q8, q9, [x9, #272]
    stp q10, q11, [x9, #304]
    stp q12, q13, [x9, #336]
    stp q14, q15, [x9, #368]

    add x10, x29, #16
    add x11, x9, #400
    mov x12, #64
Ltd_arm64_copy_stack:
    ldr x13, [x10], #8
    str x13, [x11], #8
    subs x12, x12, #1
    b.ne Ltd_arm64_copy_stack

    add x10, x29, #16
    str x10, [x9, #912]
    ldr x10, [x9, #80]
    str x10, [x9, #920]
    str x20, [x9, #928]
    str x21, [x9, #936]
    str xzr, [x9, #944]
    str x21, [x9, #1016]

    mov x0, x9
    bl SYMBOL(td_swift_trampoline_handler)

    mov x9, sp
    ldr x0, [x9, #952]
    ldr x1, [x9, #960]
    ldr x2, [x9, #968]
    ldr x3, [x9, #976]
    ldr d0, [x9, #984]
    ldr d1, [x9, #992]
    ldr d2, [x9, #1000]
    ldr d3, [x9, #1008]
    ldr x21, [x9, #1016]
    ldr x20, [x9, #928]

    add sp, sp, #1024
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
    subq $1024, %rsp
    movq %rsp, %rax

    movq %r11, 0(%rax)

    movq %rdi, 16(%rax)
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

    movdqu %xmm0, 144(%rax)
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

    leaq 16(%rbp), %rsi
    leaq 400(%rax), %rdi
    movl $64, %ecx
    rep movsq

    leaq 16(%rbp), %rcx
    movq %rcx, 912(%rax)
    movq $0, 920(%rax)
    movq %r13, 928(%rax)
    movq %r12, 936(%rax)
    movq $0, 944(%rax)
    movq %r12, 1016(%rax)

    movq %rax, %rdi
    callq SYMBOL(td_swift_trampoline_handler)

    movq %rsp, %r10
    movq 952(%r10), %rax
    movq 960(%r10), %rdx
    movq 968(%r10), %rcx
    movq 976(%r10), %r8
    movsd 984(%r10), %xmm0
    movsd 992(%r10), %xmm1
    movsd 1000(%r10), %xmm2
    movsd 1008(%r10), %xmm3
    movq 1016(%r10), %r12
    movq 928(%r10), %r13

    leave
    retq

#endif

_TEXT$ALIGNED segment align(64) alias(".text")
    public thread_set_context
    public thread_switch_context
    public thread_switch_context_implicit
    public thread_execution_context_start_trampoline
    public sleep_in_user_mode

    rbp_slot equ 8
    rip_slot equ 8

    execution_context_size             equ 224
    execution_context_create_info_size equ 16

    align 64

    ;   /// Sets current thread context to a new one discarding active.
    ;
    ;   @param activate       - A suspended context that should be activated.
    ;   @param resume_context - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
    ;
    ;   jai prototype
    ;       thread_set_context :: (
    ;           activate       : ExecutionContext,
    ;           resume_context : ResumeContext
    ;       ) #foreign self_assembly;
    ;
    thread_set_context proc
        ; Load new context.
        mov       rbx, [rcx + (8 * 0)]
        mov       rbp, [rcx + (8 * 1)]
        mov       rdi, [rcx + (8 * 2)]
        mov       rsi, [rcx + (8 * 3)]
        mov       r12, [rcx + (8 * 4)]
        mov       r13, [rcx + (8 * 5)]
        mov       r14, [rcx + (8 * 6)]
        mov       r15, [rcx + (8 * 7)]
        vmovaps  xmm6, [rcx + (8 * 8 + 16 * 0)]
        vmovaps  xmm7, [rcx + (8 * 8 + 16 * 1)]
        vmovaps  xmm8, [rcx + (8 * 8 + 16 * 2)]
        vmovaps  xmm9, [rcx + (8 * 8 + 16 * 3)]
        vmovaps xmm10, [rcx + (8 * 8 + 16 * 4)]
        vmovaps xmm11, [rcx + (8 * 8 + 16 * 5)]
        vmovaps xmm12, [rcx + (8 * 8 + 16 * 6)]
        vmovaps xmm13, [rcx + (8 * 8 + 16 * 7)]
        vmovaps xmm14, [rcx + (8 * 8 + 16 * 8)]
        vmovaps xmm15, [rcx + (8 * 8 + 16 * 9)]

        mov rsp, rcx ; Set new stack frame.
        mov rax, rdx ; Set resume context.

        mov r8, [rsp + execution_context_size + rbp_slot]     ; Load return address.
        add rsp, execution_context_size + rbp_slot + rip_slot ; For some reason, branch predictor likes 'jmp' more rather than doing canonical 'ret'.
        jmp r8
    thread_set_context endp

    align 64

    ;   /// Performs switch to a suspended context.
    ;
    ;   @param activate       - A suspended context that should be activated.
    ;   @param resume_payload - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
    ;
    ;   @return Context of the control flow regain (aka switchback).
    ;
    ;   jai prototype
    ;       switch_context :: (
    ;           activate       : ExecutionContext,
    ;           resume_payload : u64
    ;       ) -> ResumeContext #foreign self_assembly "switch_context";
    ;
    thread_switch_context proc
        ; RBP slot is allocated only for alignment.
        sub rsp, rbp_slot + execution_context_size

        ; Save current context.
        mov     [rsp + (8 * 0)],          rbx
        mov     [rsp + (8 * 1)],          rbp
        mov     [rsp + (8 * 2)],          rdi
        mov     [rsp + (8 * 3)],          rsi
        mov     [rsp + (8 * 4)],          r12
        mov     [rsp + (8 * 5)],          r13
        mov     [rsp + (8 * 6)],          r14
        mov     [rsp + (8 * 7)],          r15
        vmovaps [rsp + (8 * 8 + 16 * 0)], xmm6
        vmovaps [rsp + (8 * 8 + 16 * 1)], xmm7
        vmovaps [rsp + (8 * 8 + 16 * 2)], xmm8
        vmovaps [rsp + (8 * 8 + 16 * 3)], xmm9
        vmovaps [rsp + (8 * 8 + 16 * 4)], xmm10
        vmovaps [rsp + (8 * 8 + 16 * 5)], xmm11
        vmovaps [rsp + (8 * 8 + 16 * 6)], xmm12
        vmovaps [rsp + (8 * 8 + 16 * 7)], xmm13
        vmovaps [rsp + (8 * 8 + 16 * 8)], xmm14
        vmovaps [rsp + (8 * 8 + 16 * 9)], xmm15

        ; Load new context.
        mov       rbx, [rcx + (8 * 0)]
        mov       rbp, [rcx + (8 * 1)]
        mov       rdi, [rcx + (8 * 2)]
        mov       rsi, [rcx + (8 * 3)]
        mov       r12, [rcx + (8 * 4)]
        mov       r13, [rcx + (8 * 5)]
        mov       r14, [rcx + (8 * 6)]
        mov       r15, [rcx + (8 * 7)]
        vmovaps  xmm6, [rcx + (8 * 8 + 16 * 0)]
        vmovaps  xmm7, [rcx + (8 * 8 + 16 * 1)]
        vmovaps  xmm8, [rcx + (8 * 8 + 16 * 2)]
        vmovaps  xmm9, [rcx + (8 * 8 + 16 * 3)]
        vmovaps xmm10, [rcx + (8 * 8 + 16 * 4)]
        vmovaps xmm11, [rcx + (8 * 8 + 16 * 5)]
        vmovaps xmm12, [rcx + (8 * 8 + 16 * 6)]
        vmovaps xmm13, [rcx + (8 * 8 + 16 * 7)]
        vmovaps xmm14, [rcx + (8 * 8 + 16 * 8)]
        vmovaps xmm15, [rcx + (8 * 8 + 16 * 9)]

        mov rax, rsp ; Set previous stack frame as resume context.
        xor rax, rdx ; Append resume payload.
        mov rsp, rcx ; Set new stack frame.

        mov r8, [rsp + execution_context_size + rbp_slot]     ; Load return address.
        add rsp, execution_context_size + rbp_slot + rip_slot ; For some reason, branch predictor likes 'jmp' more than doing canonical 'ret'.
        jmp r8
    thread_switch_context endp

    align 64

    ;   /// Performs switch to a suspended context.
    ;
    ;   @Discussion:
    ;       This function does not set resume context data pointer to suspended context. Instead, it will save it
    ;       to the provided savepoint allowing setting resume context to any arbitrary data.
    ;
    ;       This function should not be a part of any high level API, as it gives too much control over context switch,
    ;       making it very bug-prone in environments that were not carefully validated.
    ;
    ;   @param savepoint      - Savepoint for the handle of the context being suspended.
    ;   @param activate       - Context that should be activated.
    ;   @param resume_context - Resume context of the switch.
    ;
    ;   @return Context of the control flow regain (aka switchback).
    ;
    ;
    ;   jai prototype:
    ;       thread_switch_context_implicit :: (
    ;           savepoint      : *ExecutionContext,
    ;           activate       : ExecutionContext,
    ;           resume_payload : u64
    ;       ) -> ResumeContext #foreign self_assembly "thread_windows_x64";
    ;
    thread_switch_context_implicit proc
        ; RBP slot is allocated only for alignment.
        mov r10, [rdx + (8 * 0)]
        sub rsp, rbp_slot + execution_context_size

        ; Save current context.
        mov     [rsp + (8 * 0)],          rbx
        mov     [rsp + (8 * 1)],          rbp
        mov     [rsp + (8 * 2)],          rdi
        mov     [rsp + (8 * 3)],          rsi
        mov     [rsp + (8 * 4)],          r12
        mov     [rsp + (8 * 5)],          r13
        mov     [rsp + (8 * 6)],          r14
        mov     [rsp + (8 * 7)],          r15
        vmovaps [rsp + (8 * 8 + 16 * 0)], xmm6
        vmovaps [rsp + (8 * 8 + 16 * 1)], xmm7
        vmovaps [rsp + (8 * 8 + 16 * 2)], xmm8
        vmovaps [rsp + (8 * 8 + 16 * 3)], xmm9
        vmovaps [rsp + (8 * 8 + 16 * 4)], xmm10
        vmovaps [rsp + (8 * 8 + 16 * 5)], xmm11
        vmovaps [rsp + (8 * 8 + 16 * 6)], xmm12
        vmovaps [rsp + (8 * 8 + 16 * 7)], xmm13
        vmovaps [rsp + (8 * 8 + 16 * 8)], xmm14
        vmovaps [rsp + (8 * 8 + 16 * 9)], xmm15

        ; Load new context.
        mov       rbx, [rdx + (8 * 0)]
        mov       rbp, [rdx + (8 * 1)]
        mov       rdi, [rdx + (8 * 2)]
        mov       rsi, [rdx + (8 * 3)]
        mov       r12, [rdx + (8 * 4)]
        mov       r13, [rdx + (8 * 5)]
        mov       r14, [rdx + (8 * 6)]
        mov       r15, [rdx + (8 * 7)]
        vmovaps  xmm6, [rdx + (8 * 8 + 16 * 0)]
        vmovaps  xmm7, [rdx + (8 * 8 + 16 * 1)]
        vmovaps  xmm8, [rdx + (8 * 8 + 16 * 2)]
        vmovaps  xmm9, [rdx + (8 * 8 + 16 * 3)]
        vmovaps xmm10, [rdx + (8 * 8 + 16 * 4)]
        vmovaps xmm11, [rdx + (8 * 8 + 16 * 5)]
        vmovaps xmm12, [rdx + (8 * 8 + 16 * 6)]
        vmovaps xmm13, [rdx + (8 * 8 + 16 * 7)]
        vmovaps xmm14, [rdx + (8 * 8 + 16 * 8)]
        vmovaps xmm15, [rdx + (8 * 8 + 16 * 9)]

        mov [rcx], rsp ; Save handle of the suspended context to the provided storage.
        mov rsp, rdx   ; Set new stack frame.
        mov rax, r8    ; Set resume context.

        mov r9, [rsp + execution_context_size + rbp_slot]     ; Load return address.
        add rsp, execution_context_size + rbp_slot + rip_slot ; For some reason, branch predictor likes 'jmp' more rather than doing canonical 'ret'.
        jmp r9
    thread_switch_context_implicit endp

    align 64

    ; /// Starts a newly created context by rewiring return values from {set, switch}_context to procedure call arguments.
    thread_execution_context_start_trampoline proc
        mov rcx, rax           ; Set resume context.
        mov rdx, [rsp + 8 * 0] ; Set invocation payload.
        mov r8,  [rsp + 8 * 1] ; Load context startup function.
        add rsp, rip_slot + execution_context_create_info_size
        jmp r8
    thread_execution_context_start_trampoline endp

    align 64

    ; /// Wait for the specified time in cycles.
    sleep_in_user_mode proc
        rdtsc             ; Read current TSC.

        shl rdx, 32       ; Load hi part in the upper 32 bits of rdx.
        xor rdx, rax      ; Load lo part in the lower 32 bits of rdx.
        add rdx, rcx      ; Append requested wait time to the deadline.
        mov eax, edx      ; Load lo part back to eax.
        shr rdx, 32       ; Load hi part back to edx.

        xor    r10d, r10d ; Make tpause to execute in C0.2 state.
        tpause r10d       ; Pause or yield to another thread on the core.

        ret
    sleep_in_user_mode endp
_TEXT$ALIGNED ends

end

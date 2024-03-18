_TEXT$aligned64 segment align(64)
    public switch_context
    public switch_context_implicit
    public execution_context_trampoline

    rbp_slot equ 8
    rip_slot equ 8

    execution_context_size equ 224

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
    switch_context proc
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
        or  rax, rdx ; Append resume payload.
        mov rsp, rcx ; Set new stack frame.

        mov r8, [rsp + execution_context_size + rbp_slot]     ; Load return address.
        add rsp, execution_context_size + rbp_slot + rip_slot ; For some reason, branch predictor likes 'jmp' more than doing canonical 'ret'.
        jmp r8
    switch_context endp

    align 64

    ;   /// Performs switch to a suspended context.
    ;
    ;   @Remarks:
    ;       Resume context of the activated context will not contain information the about suspended context as the resume is perfomed in implicit mode.
    ;
    ;   @param suspend        - Place where to save handle to the suspended context.
    ;   @param activate       - Newly created context that should be activated.
    ;   @param resume_payload - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
    ;
    ;   @return Context of the control flow regain (aka switchback).
    ;
    ;   jai prototype:
    ;       switch_context_implicit :: (
    ;           suspend        : *ExecutionContext,
    ;           activate       : ExecutionContext,
    ;           resume_payload : u64
    ;       ) -> ResumeContext #foreign self_assembly "switch_context_implicit";
    ;
    switch_context_implicit proc
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
        xor rax, rax   ; Clear resume context.
        or  rax, rdx   ; Append resume payload.
        mov rsp, rdx   ; Set new stack frame.

        mov r9, [rsp + execution_context_size + rbp_slot]     ; Load return address.
        add rsp, execution_context_size + rbp_slot + rip_slot ; For some reason, branch predictor likes 'jmp' more rather than doing canonical 'ret'.
        jmp r9
    switch_context_implicit endp

    align 64

    ; @Todo: doc
    execution_context_trampoline proc
        mov rcx, rax           ; Set resume context.
        mov rdx, [rsp + 8 * 0] ; Set invocation payload.
        mov r8,  [rsp + 8 * 1] ; Load context startup function.
        add rsp, 24
        jmp r8
    execution_context_trampoline endp

_TEXT$aligned64 ENDS

end

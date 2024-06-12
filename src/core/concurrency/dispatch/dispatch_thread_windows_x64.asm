_TLS segment align(64) alias(".tls$AAB") ; Mimicking for C/C++ thread local variables requires data to be placed after _tls_start which is stored in .tls$AAA.
    align 64

    dispatch_thread_context_reserved_size equ 64
    dispatch_thread_context DB dispatch_thread_context_reserved_size dup(0)
_TLS ends

extern _tls_index:DWORD

_TEXT$ALIGNED segment align(64) alias(".text")
    public get_dispatch_thread_context

    align 64

    ; /// Returns runtime context of the current dispatch thread.
    get_dispatch_thread_context proc
        mov edx, DWORD PTR _tls_index
        mov rcx, QWORD PTR gs:[58h]
        mov eax, sectionrel dispatch_thread_context
        add rax, [rcx + rdx * 8]
        ret
    get_dispatch_thread_context endp
_TEXT$ALIGNED ends

end

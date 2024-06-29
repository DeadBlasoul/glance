#assert OS  == .WINDOWS "This file must be loaded for Windows targets only";
#assert CPU == .X64     "This file must be loaded for x64 targets only";

ExecutionContextOpaque :: #type,distinct void;
ExecutionContext       :: *ExecutionContextOpaque;

execution_context_size              :: 224;
execution_context_address_alignment :: 16;
execution_context_memory_alignment  :: cache_line_size;
execution_context_memory_min_size   :: 64 * 1024; // 64 KB

/// Allocates memory eligible for execution stack. Guard pages are appended.
/**
 * @return: memory - Complete memory range including guard pages. This must be passed to `thread_release_stack_memory` in order of releasing allocated memory.
 *          stack  - Stack memory range.
 */
thread_allocate_stack_memory :: (size : s64) -> (memory : []u8, stack : []u8) {
    // @Todo: Ask windows about the size?
    PAGE_SIZE :: 4096;

    assert(size > 0);
    assert(size % PAGE_SIZE == 0);

    //
    // Allocate memory with required size appending guard pages.
    //
    memory_base := cast(*u8) VirtualAlloc(null, xx (size + 2 * PAGE_SIZE), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    assert(memory_base != null);

    //
    // Setup guard pages.
    //
    old_protect : DWORD;
    VirtualProtect(memory_base                   , xx PAGE_SIZE, PAGE_NOACCESS, *old_protect);
    VirtualProtect(memory_base + size + PAGE_SIZE, xx PAGE_SIZE, PAGE_NOACCESS, *old_protect);

    memory : []u8 = ---;
    memory.data   = memory_base;
    memory.count  = PAGE_SIZE + size + PAGE_SIZE;

    stack : []u8 = ---;
    stack.data   = memory_base + PAGE_SIZE;
    stack.count  = size;

    return memory, stack;
}

thread_release_stack_memory :: (memory : []u8) {
    VirtualFree(memory.data, cast(u64) memory.count, MEM_RELEASE);
}

thread_create_execution_context :: (
    memory       : []u8,
    context_data : *void,
    context_proc : (resume_context : ResumeContext, context_data : *void) -> () #c_call
) -> ExecutionContext {
    assert(memory.data & -execution_context_memory_alignment == memory.data);
    assert(memory.count >= execution_context_memory_min_size);

    stack := as_stack_aligned(memory, execution_context_memory_alignment);

    // We cannot create a new context and just give it execution control before it actually started its execution.
    // The easiest way to workaround it would be to spoof a context that called thread_switch_context.
    //
    // So, to implement it we will use `thread_execution_context_start_trampoline` as return point from fake thread_switch_context call.
    // It will rewire resume context and user data pointer as procedure call arguments leaving stack at [+0x18] when jump to user code is made.
    //
    // The following diagram shows stack state that we need:
    // +----------------------------+
    // |        pushed rip          |  [+0x18, +0x20)
    // |     pushed rbp (unused)    |  [+0x10, +0x18)
    // | ExecutionContextCreateInfo |  [+0x00, +0x10) <- prev frame addr, aligned by 16
    // +----------------------------+
    // |        pushed rip          |  [-0x08, +0x00)
    // |     pushed rbp (unused)    |  [-0x10, -0x08)
    // |       fake context         |  [-0xF0, -0x10) <- new rsp will be set here, still aligned by 16
    // +----------------------------+

    //
    // Allocation 1: Trampoline frame.
    //

    allocate_on_stack_aligned(*stack, *void, 8).* = null; // Saved rip
    allocate_on_stack_aligned(*stack, *void, 8).* = null; // Saved rbp

    assert(stack_pointer_is_aligned(stack, execution_context_address_alignment));
    #assert size_of(ExecutionContextCreateInfo) & (execution_context_address_alignment - 1) == 0;
    execution_context_create_info  := allocate_on_stack_aligned(*stack, ExecutionContextCreateInfo, execution_context_memory_alignment);
    execution_context_create_info.* = .{
        user_data     = context_data,
        user_function = context_proc,
    };

    assert(stack_pointer_is_aligned(stack, execution_context_address_alignment));

    //
    // Allocation 2: Fake `thread_switch_context` frame.
    //

    new_execution_context : ExecutionContext;
    {
        allocate_on_stack_aligned(*stack, *void, 8).* = xx thread_execution_context_start_trampoline; // Saved rip
        allocate_on_stack_aligned(*stack, *void, 8);                                                  // Saved rbp

        assert(stack_pointer_is_aligned(stack, execution_context_address_alignment));
        #assert execution_context_size & (execution_context_address_alignment - 1) == 0;
        new_execution_context = xx allocate_on_stack_aligned(
            stack     = *stack,
            size      = execution_context_size,
            alignment = execution_context_address_alignment
        );
    }
    assert(stack_pointer_is_aligned(stack, execution_context_address_alignment));

    return new_execution_context;
}

/// Sets current thread context to a new one discarding active.
/**
 * @param activate       - A suspended context that should be activated.
 * @param resume_context - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
 */
thread_set_context :: (
    activate       : ExecutionContext,
    resume_context : ResumeContext
) #foreign thread_lib;

/// Performs switch to a suspended context.
/**
 *  @param activate       - A suspended context that should be activated.
 *  @param resume_payload - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
 *
 *  @return Context of the control flow regain (aka switchback).
 */
thread_switch_context :: (
    activate       : ExecutionContext,
    resume_payload : u64
) -> ResumeContext #must #foreign thread_lib;

/// Performs switch to a suspended context.
/**
 *  @Discussion:
 *      This function does not set resume context data pointer to suspended context. Instead, it will save it
 *      to the provided storage allowing setting resume context data to any arbitrary 16-byte aligned pointer.
 *
 *  @param suspend        - Place where to save handle to the suspended context.
 *  @param activate       - Context that should be activated.
 *  @param resume_context - Resume context of the switch.
 *
 *  @return Context of the control flow regain (aka switchback).
 */
thread_switch_context_implicit :: (
    suspend        : *ExecutionContext,
    activate       : ExecutionContext,
    resume_context : ResumeContext
) -> ResumeContext #foreign thread_lib;

/// Wait for the specified time in cycles.
sleep_in_user_mode :: (cycles : s64) #foreign thread_lib;

os_thread_yield :: () {
    SwitchToThread :: () -> BOOL #foreign kernel32;
    SwitchToThread();
}

// @Todo: move it somewhere else
debug_allocate_on_stack_aligned :: ($T: Type, stack: *[]u8, $initialize : bool) -> *T {
    #assert initialize == false;
    allocated   := (stack.data + stack.count - size_of(T)) & -execution_context_memory_alignment;
    stack.count  = allocated - stack.data;
    return xx allocated;
}

/// A tightly packed data structure that contains 16-byte aligned data pointer with 4-bit wide payload.
/**
 * To unpack use the following:
 *  - get_resume_context_data
 *  - get_resume_context_payload
 */
ResumeContext :: #type,distinct u64;

/// Creates a custom resume context allowing to set arbitrary resume data pointer.
/**
 *  @param resume_data    - 16-byte aligned pointer.
 *  @param resume_payload - A custom 4-bit payload. Setting any of the 60 remaining bits might lead to data corruption.
 */
create_resume_context :: inline (resume_data : *void, resume_payload : u64) -> ResumeContext #no_context {
    // @Todo: assert(resume_payload < 16, "Payload cannot exceed 4-bit storage");
    resume_data_as_u64 := cast(u64) resume_data;
    return cast(ResumeContext) (resume_data_as_u64 ^ resume_payload);
}

create_resume_context :: inline (
    resume_payload : u64
) -> ResumeContext #no_context {
    // @Todo: assert(resume_payload < 16, "Payload cannot exceed 4-bit storage");
    return cast(ResumeContext) resume_payload;
}

get_resume_context_data :: inline (resume_context : ResumeContext) -> *void #no_context {
    resume_context_s64 := cast(s64) resume_context;
    return cast(*void) (resume_context_s64 & resume_context_data_mask);
}

get_resume_context_payload :: inline (resume_context : ResumeContext) -> u64 #no_context {
    resume_context_s64 := cast(s64) resume_context;
    return cast(u64) (cast(s64) resume_context_s64 & resume_context_payload_mask);
}

#scope_file

/// Starts a newly created context by rewiring return values from thread_switch_context/_implicit to procedure call arguments.
thread_execution_context_start_trampoline :: () -> () #foreign thread_lib;

stack_pointer_is_aligned :: inline (stack : []u8, $alignment : s64) -> bool #no_context {
    return (stack.data + stack.count) & (alignment - 1) == null;
}

ExecutionContextCreateInfo :: struct {
    user_data     : *void;
    user_function : (resume_context: ResumeContext, user_data: *void) -> () #c_call;
}

resume_context_data_mask    :: -execution_context_address_alignment;
resume_context_payload_mask :: ~resume_context_data_mask;

#import "Windows";

#import "core/allocator";
#import "core/assert";
#import "core/atomic";
#import "core/compiler";

#run,stallable compile_assembly_library("thread_windows_x64");
thread_lib :: #library,no_dll "thread_windows_x64";
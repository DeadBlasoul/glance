// @Todo: Use this file as cross-platform interface?

#assert OS  == .WINDOWS "This file must be loaded for Windows targets only";
#assert CPU == .X64     "This file must be loaded for x64 targets only";

execution_context_size              :: 224;
execution_context_address_alignment :: 16;
execution_context_memory_alignment  :: cache_line_size;
execution_context_memory_min_size   :: 8 * 1024;

ExecutionContext :: #type *PlatformContextRepresentation;

/// Prepares memory blob for a new orphan execution context.
/**
 * By orphan context we mean a context that is qualified as ready to be executed, but has no entry point yet.
 * Maybe we should name it in another way, but it is what it is right now.
 */
create_context :: (memory: []u8) -> (new_context: ExecutionContext) {
    // @Todo: Core.assert(memory.data & -execution_context_memory_alignment == memory.data);
    // @Todo: Core.assert(memory.count >= execution_context_memory_min_size);

    // Stack must be aligned by 16 with offset of 8 when we making a call.
    // Offset holds return address of the previous frame, which will be null in our case.
    execution_context_memory_alignment_offset :: 8;

    new_stack_frame        := ((memory.data + memory.count) & -execution_context_memory_alignment);
    prev_frame_ret_address := cast(**void) new_stack_frame;

    // Reset previous return address because there is no an actuall call stack yet.
    prev_frame_ret_address[0] = null;
    prev_frame_ret_address[1] = null;

    return cast(ExecutionContext) new_stack_frame;
}

// @Todo: move it somewhere else
debug_allocate_stack_memory :: (stack_size: s64) -> []u8 {
    PAGE_SIZE :: 4096;

    stack_memory := VirtualAlloc(null, xx (stack_size + 2 * PAGE_SIZE), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    stack_base   := cast(*u8) stack_memory;

    old_protect : DWORD;
    VirtualProtect(stack_base                         , xx PAGE_SIZE, PAGE_NOACCESS, *old_protect);
    VirtualProtect(stack_base + stack_size + PAGE_SIZE, xx PAGE_SIZE, PAGE_NOACCESS, *old_protect);

    stack: []u8 = ---;
    stack.data  = stack_base + PAGE_SIZE;
    stack.count = stack_size;

    return stack ;
}

create_context :: (
    memory             : []u8,
    invocation_payload : *void,
    startup            : (resume_context: ResumeContext, invocation_payload: *void) -> () #c_call
) -> ExecutionContext #no_context {
    // @Todo: Core.assert(memory.data & -execution_context_memory_alignment == memory.data);
    // @Todo: Core.assert(memory.count >= execution_context_memory_min_size);

    new_stack_frame := (memory.data + memory.count) & -execution_context_memory_alignment;

    ContextStartupData :: struct {
        context_invocation_payload      : *void;
        context_startup                 : (resume_context: ResumeContext, invocation_payload: *void) -> () #c_call;
        _                               : u64;  // Unused rbp slot
        caller_next_instruction_pointer : *void;
    }

    // Allocate & set context startup data.
    new_stack_frame -= size_of(ContextStartupData);
    startup_data    := cast(*ContextStartupData) new_stack_frame;
    startup_data.*   = .{
        context_invocation_payload      = invocation_payload,
        context_startup                 = startup,
        caller_next_instruction_pointer = null,
    };

    // Allocate pointer to execution context starter.
    new_stack_frame -= size_of(**void);
    starter         := cast(**void) new_stack_frame;
    starter.*        = xx execution_context_trampoline;

    // Allocate fake execution context.
    rbp_slot        :: 8;
    new_stack_frame -= rbp_slot + execution_context_size;

    return cast(ExecutionContext) new_stack_frame;
}

/// Performs switch to a suspended context.
/**
 *  @param activate       - A suspended context that should be activated.
 *  @param resume_payload - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
 *
 *  @return Context of the control flow regain (aka switchback).
 */
switch_context :: (
    activate       : ExecutionContext,
    resume_payload : u64
) -> ResumeContext #foreign self_assembly "switch_context";

/// Performs switch to a suspended context.
/**
 *  @Remarks:
 *      Resume context of the activated context will not contain information the about suspended context as the resume is perfomed in implicit mode.
 *
 *  @param suspend        - Place where to save handle to the suspended context.
 *  @param activate       - Newly created context that should be activated.
 *  @param resume_payload - 4-bit payload that will be appended to resume context. Setting any of the 60 remaining bits is prohibited.
 *
 *  @return Context of the control flow regain (aka switchback).
 */
switch_context_implicit :: (
    suspend        : *ExecutionContext,
    activate       : ExecutionContext,
    resume_payload : u64
) -> ResumeContext #foreign self_assembly "switch_context_implicit";


ResumeContext :: #type,distinct *void;

resume_context_source_mask  :: -execution_context_address_alignment;
resume_context_payload_mask :: ~resume_context_source_mask;

/// Returns execution context that initiated the current resume. If null is returned, than the current switch was done in implicit mode.
get_resume_context_source :: inline (resume_context : ResumeContext) -> ExecutionContext #no_context {
    resume_context_data := cast(s64) resume_context;
    return cast,no_check(ExecutionContext) (
        resume_context_data & resume_context_source_mask
    );
}

get_resume_context_payload :: inline (resume_context : ResumeContext) -> u64 #no_context {
    resume_context_data := cast(s64) resume_context;
    return cast,no_check(u64) (
        resume_context_data & resume_context_payload_mask
    );
}


#scope_file


PlatformContextRepresentation :: #type,distinct void;

execution_context_trampoline :: () -> () #foreign self_assembly "execution_context_trampoline";

#run compile_self_assembly();

compile_self_assembly :: () {
    _, linker_path := find_visual_studio_in_a_ridiculous_garbage_way();

    ml64 := sprint("%/ml64.exe", linker_path);
    lib  := sprint("%/lib.exe",  linker_path);

    run_command_checked(ml64, "/c", "/Cp", "/Zd", "./execution_context_windows_x64.asm");
    run_command_checked(lib, "./execution_context_windows_x64.obj");
}

run_command_checked :: (command : ..string) {
    process_result, stdout, _ := run_command(..command, working_directory = #filepath, capture_and_return_output = true, print_captured_output = false);
    if process_result.exit_code {
        assert(false, sprint("Cannot execute command:\n%\n\n%", command, stdout));
    }
}

#import "Basic";
#import "Process";
#import "Windows";
#import "Windows_Resources";

#import "core/atomic";

self_assembly :: #library,no_dll "execution_context_windows_x64";

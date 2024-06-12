#scope_export

/// Returns linear index of the current dispatch thread. Might be not unique if there is another dispatch queue.
get_dispatch_thread_id :: inline () -> s64 #no_context {
    return get_dispatch_thread_context().dispatch_thread_index;
}

#scope_module

DispatchThread :: struct {
    #as using base : Thread.Thread;

    dispatch_queue        : *DispatchQueue;
    dispatch_thread_index : s64;
    group                 : DispatchThreadGroup;

    should_stop : bool;
}

DispatchThreadGroup :: enum {
    dispatch;
    blocking;
}

/// Sets new execution context for the current dispatch thread.
/**
 * This function wraps the raw context manipulator `thread_switch_context_implicit` with dispatching primitives
 * and keeps valid the current dispatch thread context.
 *
 * @param suspend        : Destination store place for the current ExecutionContext.
 * @param activate       : Execution context that should be activated.
 * @param resume_context : Resume context on execution controll pass.
 *
 * @return Resume context on execution control regain.
 */
switch_dispatch_thread_execution_context_implicit :: (
    savepoint      : *ExecutionContext,
    activate       : ExecutionContext,
    resume_context : DispatchResumeContext
) -> DispatchResumeContext #must #no_context {
    saved_dispatch_context := get_dispatch_thread_context().dispatch_context;

    //
    // Apply new execution context. This will invalidate all thread-local specific data,
    // so we cannot save the current thread context just before making the call.
    //
    resume_context = xx thread_switch_context_implicit(
        suspend        = savepoint,
        activate       = activate,
        resume_context = cast(ResumeContext) resume_context
    );

    //
    // Restore dispatch context.
    //
    get_dispatch_thread_context().dispatch_context = saved_dispatch_context;

    return resume_context;
}

switch_dispatch_thread_execution_context_implicit :: no_inline (
    savepoint : *ExecutionContext,
    activate  : ExecutionContext,
    reason    : DispatchResumeReason
) -> DispatchResumeContext #must #no_context {
    return switch_dispatch_thread_execution_context_implicit(
        savepoint      = savepoint,
        activate       = activate,
        resume_context = cast(DispatchResumeContext) reason
    );
}

/// Sets new execution context for the current dispatch thread. The current context handle will be passed within resume context.
/**
 * This function wraps the raw context manipulator `thread_switch_context` with dispatching primitives
 * and keeps valid the current dispatch thread context.
 *
 * @param activate       : Execution context that should be activated.
 * @param resume_context : Resume context on execution controll pass.
 *
 * @return Resume context on execution control regain.
 */
switch_dispatch_thread_execution_context_explicit :: (
    activate : ExecutionContext,
    reason   : DispatchResumeReason
) -> DispatchResumeContext #must #no_context {
    saved_dispatch_context := get_dispatch_thread_context().dispatch_context;

    //
    // Apply new execution context. This will invalidate all thread-local specific data,
    // so we cannot save the current thread context just before making the call.
    //
    resume_context : DispatchResumeContext = xx thread_switch_context(
        activate       = activate,
        resume_payload = cast(u64) reason
    );

    //
    // Restore dispatch context.
    //
    get_dispatch_thread_context().dispatch_context = saved_dispatch_context;

    return resume_context;
}

/// Discards the current execution context by setting a new one. The suspended context will never be resumed.
discard_dispatch_thread_execution_context :: inline (
    activate       : ExecutionContext,
    resume_context : DispatchResumeContext
) #no_context {
    thread_set_context(activate, cast(ResumeContext) resume_context);
}

/// Discards the current execution context by setting a new one. The suspended context will never be resumed.
discard_dispatch_thread_execution_context :: inline (
    activate      : ExecutionContext,
    resume_reason : DispatchResumeReason
) #no_context {
    thread_set_context(activate, cast(ResumeContext) resume_reason);
}

/// Thread-local state of DispatchThread.
DispatchThreadContext :: struct {
    /// Pointer to the context of the active dispatch job. Always set when a dispatchee gains execution control.
    dispatch_context             : *DispatchContext;

    /// Pointer to dispatch queue that created the current thread.
    dispatch_queue               : *DispatchQueue;
    dispatch_queue_dispatcher    : DispatchWorkQueueLocalDispatcher;
    dispatch_queue_implicit_hash : u64;

    /// Execution context of a looper that was set to this thread. If null, a new one should be allocated.
    dispatch_thread_looper       : ExecutionContext;
    dispatch_thread_index        : s64;
}
#assert size_of(DispatchThreadContext) <= dispatch_thread_context_reserved_size;

dispatch_thread_context_reserved_size :: 64;  // Expected size of the context, used in the thread-local storage implementation.

/// Returns runtime context of the current dispatch thread.
get_dispatch_thread_context :: () -> *DispatchThreadContext #foreign dispatch_thread_lib;

DispatchResumeContext :: #type,distinct ResumeContext;

DispatchResumeReason :: enum {
    resumed;
    yield;
    stop;
}

unpack_reason :: inline (resume_context : DispatchResumeContext) -> DispatchResumeReason #no_context {
    raw_resume_context := cast(ResumeContext) resume_context;
    return cast(DispatchResumeReason) get_resume_context_payload(raw_resume_context);
}

unpack_source :: inline (resume_context : DispatchResumeContext) -> ExecutionContext #no_context {
    raw_resume_context := cast(ResumeContext) resume_context;
    return cast(ExecutionContext) get_resume_context_data(raw_resume_context);
}

unpack_dispatch_context :: inline (resume_context : DispatchResumeContext) -> *DispatchContext #no_context {
    raw_resume_context := cast(ResumeContext) resume_context;
    return cast(*DispatchContext) get_resume_context_data(raw_resume_context);
}

#scope_file

#if OS == .WINDOWS && CPU == .X64 {
    #import "core/compiler";

    #run,stallable compile_assembly_library("dispatch_thread_windows_x64");
    dispatch_thread_lib :: #library,no_dll "dispatch_thread_windows_x64";
}


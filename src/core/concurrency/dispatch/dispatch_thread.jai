#scope_export

/// Returns local index of the current dispatch thread. Not unique accross different dispatch queues.
get_dispatch_thread_id :: inline () -> s64 #no_context {
    return get_dispatch_thread_context().dispatch_thread_index;
}

#scope_module

DispatchThread :: struct {
    #as using base : Thread.Thread;

    dispatch_queue        : *DispatchQueue;
    dispatch_thread_index : s64;

    should_stop : bool;
}

is_dispatch_thread :: (dispatch_thread_context : *DispatchThreadContext) -> bool #no_context {
    return dispatch_thread_context.dispatch_queue != null;
}

/// Sets new execution context for the current dispatch thread.
/**
 * This function wraps the raw context manipulator `thread_switch_context_implicit` with dispatching primitives
 * and keeps valid the current dispatch thread context.
 *
 * @param suspend        : Destination store place for the current Dispatch.
 * @param activate       : Execution context that should be activated.
 * @param resume_context : Resume context on execution controll pass.
 *
 * @return Resume context on execution control regain.
 */
switch_dispatch_thread_execution_context_implicit :: (
    savepoint                 : *DispatchSavepoint,
    activate                  : Dispatch,
    resume_context            : DispatchResumeContext,
    $$dispatch_thread_context : *DispatchThreadContext
) -> DispatchResumeContext #must #no_context #deprecated {
    #if is_constant(dispatch_thread_context) {
        #if dispatch_thread_context == null then dispatch_thread_context := get_dispatch_thread_context();
    } else {
        todo("Restore assert(dispatch_thread_context != null)");
        // assert(dispatch_thread_context != null);
    }

    todo("Restore assert(is_dispatch_thread(dispatch_thread_context))");
    // assert(is_dispatch_thread(dispatch_thread_context), "This function cannot be invoked on non-dispatch threads.");

    saved_dispatch_context := dispatch_thread_context.dispatch_context;

    //
    // Apply new execution context. This will invalidate all thread-local specific data,
    // so we cannot save the current thread context just before making the call.
    //

    resume_context = xx thread_switch_context_implicit(
        suspend        = cast(*ExecutionContext) savepoint,
        activate       = cast(ExecutionContext) activate,
        resume_context = cast(ResumeContext) resume_context
    );

    //
    // Restore dispatch context.
    //

    get_dispatch_thread_context().dispatch_context = saved_dispatch_context;

    return resume_context;
}

switch_dispatch_thread_execution_context_implicit :: inline (
    savepoint                 : *DispatchSavepoint,
    activate                  : Dispatch,
    reason                    : DispatchResumeReason,
    $$dispatch_thread_context : *DispatchThreadContext
) -> DispatchResumeContext #must #no_context {
    todo("`reason` is always compile-time evaluated; force it explicitly");

    return switch_dispatch_thread_execution_context_implicit(
        savepoint               = savepoint,
        activate                = activate,
        resume_context          = cast(DispatchResumeContext) reason,
        dispatch_thread_context = dispatch_thread_context
    );
}

switch_dispatch_thread_execution_context_implicit :: inline (
    savepoint                 : *DispatchSavepoint,
    activate                  : Dispatch,
    $reason                   : DispatchResumeReason,
    payload                   : $DispatchResumePayload,
    $$dispatch_thread_context : *DispatchThreadContext
) -> DispatchResumeContext #modify {
    if #complete reason == {
        case .resume;  return false, "Resume context with `resume` reason has no additional payload.";
        case .yield;   DispatchResumePayload = Dispatch;
        case .suspend; DispatchResumePayload = *DispatchSuspendInfo;
        case .migrate; DispatchResumePayload = *DispatchMigrateInfo;
        case .stop;    DispatchResumePayload = Dispatch;
    }
    return true;
} {
    return switch_dispatch_thread_execution_context_implicit(
        savepoint      = savepoint,
        activate       = activate,
        resume_context = xx create_resume_context(xx payload, xx reason),
        dispatch_thread_context
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
    activate : Dispatch,
    reason   : DispatchResumeReason
) -> DispatchResumeContext #must #no_context {
    saved_dispatch_context := get_dispatch_thread_context().dispatch_context;

    //
    // Apply new execution context. This will invalidate all thread-local specific data,
    // so we cannot save the current thread context just before making the call.
    //

    resume_context : DispatchResumeContext = xx thread_switch_context(
        activate       = cast(ExecutionContext) activate,
        resume_payload = cast(u64) reason
    );

    //
    // Restore dispatch context.
    //

    get_dispatch_thread_context().dispatch_context = saved_dispatch_context;

    return resume_context;
}

/// Discards the current execution context by setting a new one. The suspended context will never be resumed.
discard_dispatch_thread_execution_context_explicit :: (
    activate : Dispatch,
    $reason  : DispatchResumeReason
) #no_context {
    #assert reason == .stop "Discard action must be followed with `stop` reason.";
    _ := thread_switch_context(
        activate       = cast(ExecutionContext) activate,
        resume_payload = cast(u64) reason
    );
    unreachable();
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
    dispatch_thread_starter      : DispatchSavepoint;
    dispatch_thread_looper       : DispatchSavepoint;
    dispatch_thread_index        : s64;
}
#assert size_of(DispatchThreadContext) <= dispatch_thread_context_reserved_size;

dispatch_thread_context_reserved_size :: 64;  // Expected size of the context, used in the thread-local storage implementation.

/// Returns runtime context of the current dispatch thread.
get_dispatch_thread_context :: () -> *DispatchThreadContext #foreign dispatch_thread_lib;

DispatchResumeContext :: enum s64 {
    /// Identical to an empty resume context with reason "resumed".
    none;
}

DispatchResumeReason :: enum s64 {
    resume;
    yield;
    suspend;
    migrate;
    stop;
}

DispatchSuspendInfo :: struct {
    suspended              : DispatchSavepoint;
    pending_resume_context : DispatchResumeContext;
}

DispatchMigrateInfo :: struct {
    suspended              : DispatchSavepoint;
    another_dispatch_queue : *DispatchQueue;
}

unpack_reason :: inline (resume_context : DispatchResumeContext) -> DispatchResumeReason #no_context {
    raw_resume_context := cast(ResumeContext) resume_context;
    return cast(DispatchResumeReason) get_resume_context_payload(raw_resume_context);
}

unpack_payload :: inline (resume_context : DispatchResumeContext, $reason : DispatchResumeReason) -> $R #modify {
    if #complete reason == {
        case .resume;  return false, "Resume context with `resume` reason has no additional payload.";
        case .yield;   R = Dispatch;
        case .suspend; R = *DispatchSuspendInfo;
        case .migrate; R = *DispatchMigrateInfo;
        case .stop;    R = Dispatch;
    }
    return true;
} {
    assert(unpack_reason(resume_context) == reason, "Attempted to unpack resume context payload with descriptive reason `%` when the actual is `%`.", reason, unpack_reason(resume_context));

    raw_resume_context := cast(ResumeContext) resume_context;
    return cast(R) get_resume_context_data(raw_resume_context);
}

#scope_file

#if OS == .WINDOWS && CPU == .X64 {
    #import "core/compiler";

    #run,stallable compile_assembly_library("dispatch_thread_windows_x64");
    dispatch_thread_lib :: #library,no_dll "dispatch_thread_windows_x64";
}

#import "core/compile_time_support";
#import "core/utility";

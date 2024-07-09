WORK_POOL_CAPACITY           :: 128;
CONTEXT_MEMORY_POOL_CAPACITY :: 32;

#scope_export

DispatchQueue :: struct {
    running_threads     : s64;
    progress            : Windows.HANDLE;
    progress_finished   : Windows.HANDLE;

    dispatch_looper_allocator  : DispatchLooperAllocator(dispatch_stack_memory_size = 1 * 1024 * 1024, dispatch_memory_images_per_thread = 2);
    dispatch_work_queue        : DispatchWorkQueue;
    dispatch_thread_pool       : [..]DispatchThread;
    dispatch_side_channel_size : s64;
}

create_dispatch_queue :: (dispatch_queue : *DispatchQueue, dispatch_concurrency : s64, dispatch_side_channel_size : s64 = 1) {
    assert(dispatch_side_channel_size > 0);

    dispatch_queue.dispatch_side_channel_size = dispatch_side_channel_size;

    create_dispatch_looper_allocator(*dispatch_queue.dispatch_looper_allocator, dispatch_concurrency);
    create_queue(*dispatch_queue.dispatch_work_queue, dispatch_concurrency + dispatch_side_channel_size);

    dispatch_queue.progress          = Windows.CreateEventA(null, 0, 0, null);
    dispatch_queue.progress_finished = Windows.CreateEventA(null, 1, 0, null);
    dispatch_queue.running_threads   = dispatch_concurrency;

    Basic.array_resize(*dispatch_queue.dispatch_thread_pool, dispatch_concurrency);
    for *thread, thread_ix : dispatch_queue.dispatch_thread_pool {
        // @Todo: Reduce stack size because we don't use it anyway.
        Thread.thread_init(thread, xx dispatch_thread_starter); {
            thread.dispatch_queue        = dispatch_queue;
            thread.dispatch_thread_index = thread_ix;
        }
    }

    /* Startup threads. */
    for *thread : dispatch_queue.dispatch_thread_pool {
        Thread.thread_start(thread);
    }
}

destroy_dispatch_queue :: (using dispatch_queue: *DispatchQueue) {
    for *thread: dispatch_thread_pool {
        thread.should_stop = true;
    }

    for _: 0..running_threads - 1 {
        SetEvent(progress);
    }
    Windows.WaitForSingleObject(progress_finished, Windows.INFINITE);

    for *thread: dispatch_thread_pool {
        Windows.WaitForSingleObject(thread.windows_thread, Windows.INFINITE);
        Thread.thread_deinit(thread);
    }

    destroy_queue(*dispatch_work_queue);
    destroy_dispatch_looper_allocator(*dispatch_looper_allocator);
}

dispatch_async :: (queue: *DispatchQueue, task_context : *T, dispatch_work : (task_context : *$T) -> ()) {
    assert(task_context & dispatch_work_item_type_mask == null, "task context must be aligned by %", dispatch_work_item_type_mask + 1);

    dispatcher := create_implicit_dispatcher(queue, get_dispatch_thread_context());
    work_item  := create_dispatch_work_item(
        task_context = task_context,
        task_routine = dispatch_work
    );

    // @Todo: We have to do something about unsuccessful enqueue. If it fires in release build, we are screwed.
    success := try_enqueue(*queue.dispatch_work_queue, dispatcher, work_item);
    assert(success);

    SetEvent(queue.progress);
}

dispatch_async :: (dispatch_queue : *DispatchQueue, dispatch_work : () -> ()) {
    dispatcher := create_implicit_dispatcher(dispatch_queue, get_dispatch_thread_context());
    work_item  := create_dispatch_work_item(
        task_context = null,
        task_routine = cast((*void) -> ()) xx dispatch_work
    );

    // @Todo: We have to do something about unsuccessful enqueue. If it fires in release build, we are screwed.
    success := try_enqueue(*dispatch_queue.dispatch_work_queue, dispatcher, work_item);
    assert(success);

    SetEvent(dispatch_queue.progress);
}

#scope_file

dispatch_async :: (dispatch_queue : *DispatchQueue, dispatch : Dispatch, dispatch_thread_context : *DispatchThreadContext) {
    dispatcher    := create_implicit_dispatcher(dispatch_queue, dispatch_thread_context);
    new_work_item := create_dispatch_work_item(dispatch);

    // @Todo: We have to do something about unsuccessful enqueue. If it fires in release build, we are screwed.
    success := try_enqueue(*dispatch_queue.dispatch_work_queue, dispatcher, new_work_item);
    assert(success);

    SetEvent(dispatch_queue.progress);
}

#scope_export

DispatchMode :: enum {
    /** Attempts to schedule task with waking up any free dispatch thread */
    immediate;

    /** Attempts to schedule task without any notifications. Suspended dispatch threads won't be resumed. */
    relaxed;
}

dispatch_async_locally :: ($dispatch_mode : DispatchMode, task_context : *T, dispatch_work : (task_context : *$T) -> ()) {
    dispatch_thread_context := get_dispatch_thread_context();

    work_item := create_dispatch_work_item(
        task_context = task_context,
        task_routine = dispatch_work
    );

    // @Todo: We have to do something about unsuccessful enqueue. If it fires in release build, we are screwed.
    success := try_enqueue(*dispatch_thread_context.dispatch_queue.dispatch_work_queue, dispatch_thread_context.dispatch_queue_dispatcher, work_item);
    assert(success);

    #if dispatch_mode == .immediate {
        SetEvent(dispatch_thread_context.dispatch_queue.progress);
    }
}

yield_this_dispatch :: () {
    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_thread_looper  := query_dispatch_looper(dispatch_thread_context);

    // @Todo: parse `resume_context`
    // @Todo: pass dispatch thread context
    resume_context := switch_dispatch_thread_execution_context_explicit(activate = dispatch_thread_looper, reason = .yield);
}

migrate_this_dispatch_on :: (dispatch_queue : *DispatchQueue) {
    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_thread_looper  := query_dispatch_looper(dispatch_thread_context);

    migrate_info := DispatchMigrateInfo.{
        another_dispatch_queue = dispatch_queue
    };

    resume_context := switch_dispatch_thread_execution_context_implicit(
        savepoint = *migrate_info.suspended,
        activate  = dispatch_thread_looper,
        reason    = .migrate,
        payload   = *migrate_info,
        dispatch_thread_context
    );

    assert(unpack_reason(resume_context) == .resume);
}

#scope_module

/// Creates new implicit dispatcher for side channel in the queue.
create_implicit_dispatcher :: (dispatch_queue : *DispatchQueue, dispatch_thread_context : *DispatchThreadContext) -> DispatchWorkQueueImplicitDispatcher {
    hash := Hash.fnv1a_hash(dispatch_thread_context.dispatch_queue_implicit_hash);
    dispatch_thread_context.dispatch_queue_implicit_hash = hash;

    offset := dispatch_queue.dispatch_thread_pool.count;
    return acquire_producer_token(
        queue          = *dispatch_queue.dispatch_work_queue,
        subqueue_index = offset + xx (hash % xx dispatch_queue.dispatch_side_channel_size),  // @Cleanup: xx mess
        token_type     = DispatchWorkQueueImplicitDispatcher
    );
}

DispatchWorkQueue :: ConcurrentQueue(
    DispatchWorkItem,
    policy = ConcurrentQueuePolicy(
        capacity_per_subqueue = WORK_POOL_CAPACITY
    )
);

DispatchWorkQueueLocalDispatcher    :: ProducerToken(DispatchWorkQueue, attributes = .{ syncing = .disabled, queuing = .exclusive });
DispatchWorkQueueImplicitDispatcher :: ProducerToken(DispatchWorkQueue, attributes = .{ syncing = .enabled , queuing = .exclusive });

query_dispatch_looper :: (dispatch_thread_context : *DispatchThreadContext) -> Dispatch {
    //
    // Try extract dispatch looper from the dispatch thread context first.
    //

    dispatch_thread_looper := consume_dispatch(*dispatch_thread_context.dispatch_thread_looper);
    if dispatch_thread_looper != .invalid {
        return dispatch_thread_looper;
    }

    //
    // There was no assigned looper, create a new one.
    //

    return create_dispatch_looper(*dispatch_thread_context.dispatch_queue.dispatch_looper_allocator, dispatch_thread_context.dispatch_thread_index);
}

dispatch_thread_starter :: (thread : *DispatchThread) -> s64 {
    //
    // Setup dispatch thread context.
    //

    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_thread_context.* = .{
        dispatch_context = null,

        dispatch_queue               = thread.dispatch_queue,
        dispatch_queue_dispatcher    = acquire_producer_token(*thread.dispatch_queue.dispatch_work_queue, thread.dispatch_thread_index, token_type = DispatchWorkQueueLocalDispatcher),
        dispatch_queue_implicit_hash = cast(u64) thread.dispatch_thread_index,

        dispatch_thread_index  = thread.dispatch_thread_index,
        dispatch_thread_looper = .invalid,
    };

    // @Todo: debug, @Cleanup
    SetThreadAffinityMask(Windows.GetCurrentProcess(), 1 << (thread.dispatch_thread_index + 1));

    //
    // Invoke looper.
    //

    resume_context := switch_dispatch_thread_execution_context_implicit(
        savepoint = *dispatch_thread_context.dispatch_thread_starter,
        activate  = query_dispatch_looper(dispatch_thread_context),
        reason    = .resume,
        dispatch_thread_context
    );

    dispatch_thread_context = get_dispatch_thread_context();

    //
    // Notify that progress of current thread is finished.
    //

    dispatch_queue := dispatch_thread_context.dispatch_queue;

    // @Todo,@Cleanup: use engine primitives
    Default_Atomics :: #import "Atomics";
    if Default_Atomics.atomic_add(*dispatch_queue.running_threads, -1) == 1 { // Returns old value
        SetEvent(dispatch_queue.progress_finished);
    }

    //
    // Suspend dispatch that requested thread stop.
    //

    resume_reason   := unpack_reason(resume_context);
    source_dispatch := unpack_payload(resume_context, reason = .yield);

    assert(resume_reason == .yield);
    assert(source_dispatch != .invalid);

    suspend_dispatch_looper(source_dispatch);

    //
    // Suspend dispatch thread looper if it's set.
    //

    dispatch_thread_context = get_dispatch_thread_context();
    dispatch_thread_looper := consume_dispatch(*dispatch_thread_context.dispatch_thread_looper);

    if dispatch_thread_looper != .invalid then suspend_dispatch_looper(dispatch_thread_looper);

    return 0;
}

dispatch_looper_starter :: (resume_context : DispatchResumeContext, dispatch_context : *DispatchContext) #c_call {
    //
    // Start looping.
    //

    stop_requster : Dispatch = ---;
    jai_context   : Context;

    push_context jai_context {
        stop_requster = dispatch_looper_routine(resume_context, dispatch_context);
    }

    //
    // Finish dispatch by switching to dispatch stop requester.
    //

    discard_dispatch_thread_execution_context_explicit(
        activate = stop_requster,
        reason   = .stop
    );
}

DispatchWorkQueueConsumeToken :: ConsumerToken(DispatchWorkQueue, attributes = .{syncing = .enabled, queuing = .broadwide});

dispatch_looper_routine :: (resume_context : DispatchResumeContext, dispatch_context : *DispatchContext) -> (stop_requster : Dispatch) {
    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_queue          := dispatch_thread_context.dispatch_queue;
    dispatch_thread_index   := -1; //! Just to hit thread index check at the start of the first loop.
    dispatch_consume_token  : DispatchWorkQueueConsumeToken = ---;

    while looping := true {
        /* Processing of `stop` request cannot access any thread-local states (it's a requirement), so it must be done beforehand. */
        if unpack_reason(resume_context) == .stop then return unpack_payload(resume_context, reason = .stop);

        //
        // Check whether we've been migrated to another dispatch thread or not.
        //

        dispatch_thread_context = get_dispatch_thread_context();

        if dispatch_thread_context.dispatch_queue != dispatch_queue && dispatch_context.allocation_slot != .system {
            /* Far away move has happened. We would like to stop the current dispatch and release it back to homeland. */
            resume_context = suspend_current_dispatch(resume_context, dispatch_thread_context, on_resume = #code { dispatch_thread_context = get_dispatch_thread_context(); });

            /* Make sure that we actually moved to our own dispatch queue. */
            assert(dispatch_thread_context.dispatch_queue == dispatch_queue);
        } else {
            /* The allocation source is system, so no difference what dispatch queue allocated this dispatch; we can move on just fine. */
            dispatch_queue = dispatch_thread_context.dispatch_queue;
        }

        if dispatch_thread_context.dispatch_thread_index != dispatch_thread_index {
            dispatch_thread_index  = dispatch_thread_context.dispatch_thread_index;
            dispatch_consume_token = acquire_consumer_token(*dispatch_queue.dispatch_work_queue, subqueue_index = dispatch_thread_index, token_type = DispatchWorkQueueConsumeToken);
        }

        //
        // Process resume context.
        //

        while processing_resume_context := true {
            if #complete unpack_reason(resume_context) == {
                case .resume;
                    // No-op.

                case .yield;
                    /* @Warning: In the current design, yield has a greater priority since it does local dispatching before next consuming.
                                 If there are no jobs in the local queue, yielded dispatch will regain execution despite existing of other tasks globally.

                                 As a side effect, yield might overflow local queue. We could've make pre-consume, but it increases memory pressure on allocation system.
                                 To prevent any unexpected outcomes, such an overflow would terminate the app even if we are running a release build. */

                    yielded_dispatch := unpack_payload(resume_context, reason = .yield);
                    new_work_item    := create_dispatch_work_item(yielded_dispatch);

                    if !try_enqueue(*dispatch_queue.dispatch_work_queue, *dispatch_thread_context.dispatch_queue_dispatcher, new_work_item) then trigger_access_violation();

                case .suspend;
                    suspend_info := unpack_payload(resume_context, .suspend);
                    suspend_dispatch_looper(consume_dispatch_from_immediate(suspend_info.suspended));

                    resume_context = suspend_info.pending_resume_context;
                    continue processing_resume_context;

                case .migrate;
                    migrate_info := unpack_payload(resume_context, .migrate);
                    dispatch_async(migrate_info.another_dispatch_queue, consume_dispatch_from_immediate(migrate_info.suspended), dispatch_thread_context);

                case .stop;
                    unreachable();
            }

            break processing_resume_context;
        }

        //
        // Consume next dispatch.
        //

        work_item : DispatchWorkItem = ---;

        while consuming := true {
            if load(*dispatch_queue.dispatch_thread_pool[dispatch_thread_index].should_stop, memory_order = .acquire) {
                resume_context = switch_dispatch_thread_execution_context_explicit(
                    activate = consume_dispatch(*dispatch_thread_context.dispatch_thread_starter),
                    reason   = .yield
                );
                continue looping;
            }

            if !try_dequeue(*dispatch_queue.dispatch_work_queue, dispatch_consume_token, *work_item) {
                // @Todo: Do user mode sleep for a short period of time if available.
                Windows.WaitForSingleObject(dispatch_queue.progress, milliseconds = 1);
                continue consuming;
            }

            /* Successful consume. */
            break consuming;
        }

        //
        // Execute dispatch.
        //

        if #complete get_dispatch_work_item_type(work_item) == {
            case .dispatched_task;
                task_context, task_routine := unpack_as_dispatched_task(work_item);

                task_routine(task_context);
                Basic.reset_temporary_storage();

                resume_context = .none;

            case .dispatched_context;
                dispatch := unpack_as_dispatched_context(work_item);

                dispatch_thread_looper := consume_dispatch(*dispatch_thread_context.dispatch_thread_looper);
                if dispatch_thread_looper != .invalid then suspend_dispatch_looper(dispatch_thread_looper);

                resume_context = switch_dispatch_thread_execution_context_implicit(
                    savepoint = *dispatch_thread_context.dispatch_thread_looper,
                    activate  = dispatch,
                    reason    = .resume,
                    dispatch_thread_context
                );
        }
    }
}

suspend_current_dispatch :: (resume_context : DispatchResumeContext, dispatch_thread_context : *DispatchThreadContext, $on_resume : Code) -> DispatchResumeContext #expand {
    suspend_info := DispatchSuspendInfo.{pending_resume_context = resume_context};

    resume_context = switch_dispatch_thread_execution_context_implicit(
        savepoint = *suspend_info.suspended,
        activate  = query_dispatch_looper(dispatch_thread_context),
        reason    = .suspend,
        payload   = *suspend_info,
        dispatch_thread_context
    );

    #insert on_resume;

    return resume_context;
}

SetEvent :: (hEvent: Windows.HANDLE) -> bool #foreign kernel32;
SetThreadAffinityMask :: (h: Windows.HANDLE, mask: s64) -> Windows.BOOL #foreign;

Basic   :: #import "Basic";
Thread  :: #import "Thread";
Windows :: #import "Windows";

#import "logger";

#import "core/atomic";
#import "core/basic";
#import "core/concurrency/concurrent_queue";
#import "core/concurrency/thread";

operator - :: Basic.operator -;

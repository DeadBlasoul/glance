WORK_POOL_CAPACITY           :: 32;
CONTEXT_MEMORY_POOL_CAPACITY :: 32;

#scope_export

DispatchQueue :: struct {
    work_queue        : DispatchWorkQueue;
    running_threads   : s64;
    progress          : Windows.HANDLE;
    progress_finished : Windows.HANDLE;

    dispatch_looper_allocator : DispatchLooperAllocator(dispatch_stack_memory_size = 1 * 1024 * 1024, dispatch_memory_images_per_thread = 2);
    dispatch_thread_pool      : [..]DispatchThread;
}

create_dispatch_queue :: (using dispatch_queue : *DispatchQueue, number_of_threads : s64) {
    create_queue(*work_queue, number_of_threads);

    create_dispatch_looper_allocator(*dispatch_looper_allocator, number_of_threads);

    progress          = Windows.CreateEventA(null, 0, 0, null);
    progress_finished = Windows.CreateEventA(null, 1, 0, null);
    running_threads   = number_of_threads;

    Basic.array_resize(*dispatch_thread_pool, number_of_threads);
    for *thread, thread_ix : dispatch_thread_pool {
        // @Todo: Reduce stack size because we don't use it anyway.
        Thread.thread_init(thread, xx dispatch_thread_starter); {
            thread.dispatch_queue        = dispatch_queue;
            thread.dispatch_thread_index = thread_ix;
        }
    }
}

start_dispatch_queue :: (dispatch_queue : *DispatchQueue) {
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

    destroy_queue(*work_queue);
    destroy_dispatch_looper_allocator(*dispatch_looper_allocator);
}

dispatch_async :: (queue: *DispatchQueue, task_context : *T, dispatch_work : (task_context : *$T) -> ()) {
    assert(task_context & dispatch_work_item_type_mask == null, "task context must be aligned by %", dispatch_work_item_type_mask + 1);

    dispatcher := create_implicit_dispatcher(queue);
    work_item  := create_dispatch_work_item(
        task_context = task_context,
        task_routine = dispatch_work
    );

    success := try_enqueue(*queue.work_queue, dispatcher, work_item);
    assert(success);

    SetEvent(queue.progress);
}

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

    success := try_enqueue(*dispatch_thread_context.dispatch_queue.work_queue, dispatch_thread_context.dispatch_queue_dispatcher, work_item);
    assert(success);

    #if dispatch_mode == .immediate {
        SetEvent(dispatch_thread_context.dispatch_queue.progress);
    }
}

dispatch_yield_locally :: () {
    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_thread_looper  := query_dispatch_looper(dispatch_thread_context);

    // @Todo: parse `resume_context`
    // @Todo: pass dispatch thread context
    resume_context := switch_dispatch_thread_execution_context_explicit(activate = dispatch_thread_looper, reason = .yield);
}

#scope_module

create_implicit_dispatcher :: (dispatch_queue : *DispatchQueue) -> DispatchWorkQueueImplicitDispatcher {
    // @Todo: implement it properly
    return acquire_producer_token(*dispatch_queue.work_queue, subqueue_index = 0, token_type = DispatchWorkQueueImplicitDispatcher);
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
        dispatch_queue_dispatcher    = acquire_producer_token(*thread.dispatch_queue.work_queue, thread.dispatch_thread_index, token_type = DispatchWorkQueueLocalDispatcher),
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
        reason    = .resumed,
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
    // Release dispatch that requested thread stop.
    //

    resume_reason   := unpack_reason(resume_context);
    source_dispatch := unpack_source(resume_context);

    assert(resume_reason   == .resumed);
    assert(source_dispatch != .invalid);

    release_dispatch_looper(source_dispatch);

    //
    // Release dispatch thread looper if it's set.
    //

    dispatch_thread_context = get_dispatch_thread_context();
    dispatch_thread_looper := consume_dispatch(*dispatch_thread_context.dispatch_thread_looper);

    if dispatch_thread_looper != .invalid then release_dispatch_looper(dispatch_thread_looper);

    return 0;
}

dispatch_looper_starter :: (resume_context : DispatchResumeContext, dispatch_looper_context : *DispatchContext) #c_call {
    //
    // Start looping.
    //

    stop_requester_dispatch : Dispatch = ---;
    jai_context             : Context;

    push_context jai_context {
        stop_requester_dispatch = dispatch_looper_routine(resume_context);
    }

    //
    // Finish thread by switching back to its starter.
    //

    discard_dispatch_thread_execution_context_explicit(
        activate = stop_requester_dispatch,
        reason   = .resumed
    );
}

dispatch_looper_routine :: (resume_context : DispatchResumeContext) -> (stop_requester_dispatch : Dispatch) {
    dispatch_thread_context := get_dispatch_thread_context();

    dispatch_queue := dispatch_thread_context.dispatch_queue;
    thread_index   := dispatch_thread_context.dispatch_thread_index;

    dispatch_consume_token := acquire_consumer_token(
        queue          = *dispatch_queue.work_queue,
        subqueue_index = thread_index,
        attributes     = .{
            syncing = .enabled,
            queuing = .broadwide,
        }
    );

    process_resume_action :: (resume_context : DispatchResumeContext) #expand {
        if #complete unpack_reason(resume_context) == {
            case .resumed;
                // No-op

            case .yield;
                suspended := unpack_source(resume_context);
                work_item := create_dispatch_work_item(suspended);

                success := try_enqueue(*`dispatch_queue.work_queue, `dispatch_thread_context.dispatch_queue_dispatcher, work_item);
                assert(success);

            case .stop;
                stop_requester_dispatch := unpack_source(resume_context);
                `return stop_requester_dispatch;
        }
    }

    //
    // Preprocess resume context beforehand as it might have pending actions to account.
    //

    process_resume_action(resume_context);

    //
    // Start looping.
    //

    decide_next_sleeping_mode :: inline (sleeping_index_counter : *s64) -> enum {sleep_in_user_mode; sleep_in_kernel_mode;} #no_context {
        if sleeping_index_counter.* < 20 {
            sleeping_index_counter.* += 1;
            return .sleep_in_user_mode;
        }
        return .sleep_in_kernel_mode;
    }

    sleeping_index_counter := 0;

    while looping := true {
        work_item : DispatchWorkItem = ---;

        //
        // Consume dispatch.
        //

        if !try_dequeue(*dispatch_queue.work_queue, dispatch_consume_token, *work_item) {
            if load(*dispatch_queue.dispatch_thread_pool[thread_index].should_stop, memory_order = .acquire) {
                work_item = create_dispatch_thread_stop_request();
            } else {
                if #complete decide_next_sleeping_mode(*sleeping_index_counter) == {
                    case .sleep_in_user_mode;
                        sleep_in_user_mode(sleep_cycles = 25_000);

                    case .sleep_in_kernel_mode;
                        Windows.WaitForSingleObject(dispatch_queue.progress, milliseconds = 1);
                }
                continue looping;
            }
        }

        sleeping_index_counter = 0;

        //
        // Execute dispatch.
        //

        if #complete get_dispatch_work_item_type(work_item) == {
            case .dispatched_task;
                task_context, task_routine := unpack_as_dispatched_task(work_item);

                task_routine(task_context);
                Basic.reset_temporary_storage();

                dispatch_thread_context = get_dispatch_thread_context();

            case .dispatched_context;
                dispatched_context := unpack_as_dispatched_context(work_item);

                dispatch_thread_looper := consume_dispatch(*dispatch_thread_context.dispatch_thread_looper);
                if dispatch_thread_looper != .invalid then release_dispatch_looper(dispatch_thread_looper);

                resume_context = switch_dispatch_thread_execution_context_implicit(
                    savepoint = *dispatch_thread_context.dispatch_thread_looper,
                    activate  = dispatched_context,
                    reason    = .resumed,
                    dispatch_thread_context
                );

                dispatch_thread_context = get_dispatch_thread_context();
                process_resume_action(resume_context);

            case .dispatch_thread_stop_request;
                resume_context = switch_dispatch_thread_execution_context_explicit(
                    activate = consume_dispatch(*dispatch_thread_context.dispatch_thread_starter),
                    reason   = .resumed
                );

                dispatch_thread_context = get_dispatch_thread_context();
                process_resume_action(resume_context);
        }

        //
        // Update looper environment.
        //

        if dispatch_queue != dispatch_thread_context.dispatch_queue || thread_index != dispatch_thread_context.dispatch_thread_index {
            dispatch_queue = dispatch_thread_context.dispatch_queue;
            thread_index   = dispatch_thread_context.dispatch_thread_index;

            dispatch_consume_token = acquire_consumer_token(
                queue          = *dispatch_queue.work_queue,
                subqueue_index = thread_index,
                attributes     = .{
                    syncing = .enabled,
                    queuing = .broadwide,
                }
            );
        }
    }
}

shutdown_context :: inline (activate : Dispatch, looper_context : *DispatchContext) #deprecated "Must be removed, out of module structure" {
    thread_set_context(
        activate       = cast(ExecutionContext) activate,
        resume_context = create_resume_context(
            resume_data    = looper_context,
            resume_payload = cast(u64) DispatchResumeReason.resumed // ???
        )
    );
}

_endthreadex :: (retval : u32) #foreign;

SetEvent :: (hEvent: Windows.HANDLE) -> bool #foreign kernel32;
SetThreadAffinityMask :: (h: Windows.HANDLE, mask: s64) -> Windows.BOOL #foreign;
ExitThread :: (exit_code: u32) -> void #foreign kernel32;
SwitchToThread :: () -> Windows.BOOL #foreign kernel32;

Basic   :: #import "Basic";
Thread  :: #import "Thread";
Windows :: #import "Windows";

#import "logger";

#import "core/atomic";
#import "core/basic";
#import "core/concurrency/concurrent_queue";
#import "core/concurrency/thread";

operator - :: Basic.operator -;

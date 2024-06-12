WORK_POOL_CAPACITY           :: 32;
CONTEXT_MEMORY_POOL_CAPACITY :: 32;

#scope_export

DispatchQueue :: struct {
    work_queue        : DispatchWorkQueue;
    context_pool      : DispatchLooperPool;
    thread_pool       : [..]DispatchThread;
    running_threads   : s64;
    progress          : Windows.HANDLE;
    progress_finished : Windows.HANDLE;
}

create_dispatch_queue :: (using dispatch_queue : *DispatchQueue, number_of_threads : s64) {
    create_queue(*work_queue, number_of_threads);
    create_queue(*context_pool, number_of_threads);

    // @Cleanup
    // dispatcher := acquire_producer_token(*context_pool, 0, attributes = .{ syncing = .disabled, queuing = .exclusive });
    // for i : 1..32 {
    //     own_execution_context, dispatch_context := dispatch_create_context(queue);

    //     dispatch_context.task                  = null;
    //     dispatch_context.task_context          = null;
    //     dispatch_context.own_execution_context = own_execution_context;

    //     try_enqueue(*context_pool, dispatcher, dispatch_context);
    // }

    progress          = Windows.CreateEventA(null, 0, 0, null);
    progress_finished = Windows.CreateEventA(null, 1, 0, null);
    running_threads   = number_of_threads;

    Basic.array_resize(*thread_pool, number_of_threads);
    for *thread, thread_ix : thread_pool {
        // @Todo: Reduce stack size because we don't use it anyway.
        Thread.thread_init(thread, xx dispatch_thread_starter); {
            thread.dispatch_queue        = dispatch_queue;
            thread.dispatch_thread_index = thread_ix;
        }
    }
}

create_dispatch_queue :: (
    dispatch_queue               : *DispatchQueue,
    dispatch_threads_count       : s64,
    blocking_threads_count       : s64,
    external_enqueue_lines_count : s64
) {
    total_number_of_threads := dispatch_threads_count + blocking_threads_count;

    create_queue(*dispatch_queue.dispatch_work_queue,   number_of_subqueues = total_number_of_threads + external_enqueue_lines_count);
    create_queue(*dispatch_queue.dispatch_loopers_pool, number_of_subqueues = total_number_of_threads);

    setup_thread_context_allocator(*dispatch_queue.thread_context_allocator, dispatch_threads_count + blocking_threads_count);

    create_os_event(*dispatch_queue.progress);
    create_os_event(*dispatch_queue.progress_finished);

    Basic.array_resize(*dispatch_queue.dispatch_threads_pool, dispatch_threads_count, initialize = false);
    for *thread, dispatch_thread_index : dispatch_queue.dispatch_threads_pool {
        thread.* = .{
            dispatch_queue        = dispatch_queue,
            dispatch_thread_index = dispatch_thread_index,
            group                 = .dispatch,
        };
        Thread.thread_init(thread, xx dispatch_thread_starter);
    }

    Basic.array_resize(*dispatch_queue.blocking_threads_pool, blocking_threads_count, initialize = false);
    for *thread, blocking_thread_index : dispatch_queue.blocking_threads_pool {
        thread.* = .{
            dispatch_queue        = dispatch_queue,
            dispatch_thread_index = dispatch_threads_count + external_enqueue_lines_count + blocking_thread_index,
            group                 = .blocking,
        };
        Thread.thread_init(thread, xx dispatch_thread_starter);
    }
}

start_dispatch_queue :: (dispatch_queue : *DispatchQueue) {
    for *thread : dispatch_queue.thread_pool {
        Thread.thread_start(thread);
    }
}

destroy_dispatch_queue :: (using dispatch_queue: *DispatchQueue) {
    for *thread: thread_pool {
        thread.should_stop = true;
    }

    for _: 0..running_threads - 1 {
        SetEvent(progress);
    }
    Windows.WaitForSingleObject(progress_finished, Windows.INFINITE);

    for *thread: thread_pool {
        Windows.WaitForSingleObject(thread.windows_thread, Windows.INFINITE);
        Thread.thread_deinit(thread);
    }

    // @Cleanup
    // dispatch_context : *DispatchWorkItemContext = ---;
    // consumer_token   := acquire_consumer_token(*context_pool, 0, attributes = .{ syncing = .external, queuing = .broadwide });
    // while try_dequeue(*context_pool, consumer_token, *dispatch_context) {
    //     // @Fixme: MEMORY LEAK - there might be non-deallocated data in the jai context used in this execution context. Stop context properly before releasing memory.
    //     debug_release_stack_memory(dispatch_context.memory);
    // }

    destroy_queue(*context_pool);
    destroy_queue(*work_queue);
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

    success := try_enqueue(*dispatch_thread_context.dispatch_queue.work_queue, dispatch_thread_context.thread_dispatcher, work_item);
    assert(success);

    #if dispatch_mode == .immediate {
        SetEvent(dispatch_thread_context.dispatch_queue.progress);
    }
}

dispatch_yield_locally :: () {
    dispatch_thread_context := get_dispatch_thread_context();

    // Consume thread looper
    thread_looper := dispatch_thread_context.dispatch_thread_looper;
    dispatch_thread_context.dispatch_thread_looper = null;

    if thread_looper == null {
        thread_looper = query_dispatch_looper(dispatch_thread_context.dispatch_queue, dispatch_thread_context.dispatch_thread_index);
    }

    resume_context := switch_dispatch_thread_execution_context_explicit(activate = thread_looper, reason = .yield);
    // @Todo: parse `resume_context`
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

DispatchLooperPool :: ConcurrentQueue(
    ExecutionContext,
    policy = ConcurrentQueuePolicy(
        capacity_per_subqueue = CONTEXT_MEMORY_POOL_CAPACITY
    )
);

DispatchLooperPoolProduceToken :: ProducerToken(DispatchLooperPool, attributes = .{ syncing = .disabled, queuing = .exclusive });
DispatchLooperPoolConsumeToken :: ConsumerToken(DispatchLooperPool, attributes = .{ syncing = .enabled,  queuing = .broadwide });

create_dispatch_looper :: (queue : *DispatchQueue) -> ExecutionContext #deprecated "implementation is outdated" {
    // @Todo: proper stack size
    memory, stack := thread_allocate_stack_memory(execution_context_memory_min_size + 4096);

    looper_dispatch_context  := debug_allocate_on_stack_aligned(DispatchContext, *stack);
    looper_dispatch_context.* = .{
        stack_memory       = memory,
        stack_memory_owner = queue,
    };

    return thread_create_execution_context(stack, looper_dispatch_context, xx dispatch_looper_starter);
}

query_dispatch_looper :: (dispatch_queue : *DispatchQueue, thread_index : s64) -> ExecutionContext #deprecated "Use new version instead" {
    context_acquire_token := acquire_consumer_token(
        queue          = *dispatch_queue.context_pool,
        subqueue_index = thread_index,
        token_type     = DispatchLooperPoolConsumeToken
    );

    free_looper : ExecutionContext = ---;
    if !try_dequeue(*dispatch_queue.context_pool, context_acquire_token, *free_looper) {
        free_looper = create_dispatch_looper(dispatch_queue);
    }

    return free_looper;
}

query_dispatch_looper :: () -> ExecutionContext {
    dispatch_thread_context := get_dispatch_thread_context();

    //
    // There might be already assigned dispatch looper for this thread. Try to return it.
    //
    dispatch_thread_looper                         := dispatch_thread_context.dispatch_thread_looper;
    dispatch_thread_context.dispatch_thread_looper  = null;
    if dispatch_thread_looper != null {
        return dispatch_thread_looper;
    }

    //
    // There is no assigned looper. Query from the pool or create a new one.
    //
    dispatch_queue                := dispatch_thread_context.dispatch_queue;
    dispatch_thread_index         := dispatch_thread_context.dispatch_thread_index;
    dispatch_looper_consume_token := acquire_consumer_token(
        queue          = *dispatch_queue.context_pool,
        subqueue_index = dispatch_thread_index,
        token_type     = DispatchLooperPoolConsumeToken
    );
    if !try_dequeue(*dispatch_queue.context_pool, dispatch_looper_consume_token, *dispatch_thread_looper) {
        dispatch_thread_looper = create_dispatch_looper(dispatch_queue);
    }

    return dispatch_thread_looper;
}

dispatch_thread_starter :: (thread : *DispatchThread) -> s64 {
    dispatch_thread_context := get_dispatch_thread_context();
    dispatch_thread_context.* = .{
        dispatch_context = null,

        dispatch_queue               = thread.dispatch_queue,
        dispatch_queue_dispatcher    = acquire_producer_token(*thread.dispatch_queue.work_queue, thread.dispatch_thread_index, token_type = DispatchWorkQueueLocalDispatcher),
        dispatch_queue_implicit_hash = cast(u64) thread.dispatch_thread_index,

        dispatch_thread_index  = thread.dispatch_thread_index,
        dispatch_thread_looper = null,
    };

    // @Todo: debug, @Cleanup
    SetThreadAffinityMask(Windows.GetCurrentProcess(), 1 << (thread.dispatch_thread_index + 1));

    // The stack provided by the OS is unusable, because it's allocated by the OS and will be destroyed by the OS.
    // We have to switch to our own context, otherwise we would not be able to migrate current stack to another thread.
    discard_dispatch_thread_execution_context(
        activate      = query_dispatch_looper(thread.dispatch_queue, thread.dispatch_thread_index),
        resume_reason = .resumed
    );

    // @Unreachable
    return -1;
}

dispatch_looper_starter :: (resume_context : DispatchResumeContext, looper_dispatch_context : *DispatchContext) #c_call {
    jai_context : Context;
    push_context jai_context {
        dispatch_looper_routine(resume_context, looper_dispatch_context);
    }
}

dispatch_looper_routine :: (resume_context : DispatchResumeContext, looper_dispatch_context : *DispatchContext) {
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

    looper_release_token := acquire_producer_token(
        queue          = *dispatch_queue.context_pool,
        subqueue_index = thread_index,
        attributes     = .{
            syncing = .disabled,
            queuing = .exclusive,
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
                source_context := unpack_source(resume_context);
                shutdown_context(activate = source_context, `looper_dispatch_context);
        }
    }

    //
    // Parse resume context beforehand. There might be pending actions that are required to be processed before starting the loop.
    //
    process_resume_action(resume_context);

    //
    // Main loop.
    //
    while load(*dispatch_queue.thread_pool[thread_index].should_stop, memory_order = .acquire) == false {
        work_item : DispatchWorkItem = ---;
        if !try_dequeue(*dispatch_queue.work_queue, *dispatch_consume_token, *work_item) {
            Windows.WaitForSingleObject(dispatch_queue.progress, Windows.INFINITE);
            continue;
        }

        //
        // Execute dispatched job.
        //
        if #complete get_dispatch_work_item_type(work_item) == {
            case .dispatched_task;
                task_context, task_routine := unpack_as_dispatched_task(work_item);
                task_routine(task_context);
                Basic.reset_temporary_storage();

            case .dispatched_context;
                dispatched_context := unpack_as_dispatched_context(work_item);

                if dispatch_thread_context.dispatch_thread_looper {
                    // The current thread local looper will be replaced by the current execution context.
                    if !try_enqueue(*dispatch_queue.context_pool, looper_release_token, dispatch_thread_context.dispatch_thread_looper) {
                        finished_looper_context := shutdown_dispatch_looper(dispatch_thread_context.dispatch_thread_looper);
                        thread_release_stack_memory(finished_looper_context.stack_memory);
                    }
                }

                resume_context = switch_dispatch_thread_execution_context_implicit(
                    savepoint = *dispatch_thread_context.dispatch_thread_looper,
                    activate  = dispatched_context,
                    reason    = .resumed
                );
                process_resume_action(resume_context);
        }

        //
        // Update current context as it might be changed.
        //
        dispatch_thread_context = get_dispatch_thread_context();
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

            looper_release_token = acquire_producer_token(
                queue          = *dispatch_queue.context_pool,
                subqueue_index = thread_index,
                attributes     = .{
                    syncing = .disabled,
                    queuing = .exclusive,
                }
            );
        }
    }

    // @Todo,@Cleanup: use engine primitives
    #import "Atomics";
    if atomic_add(*dispatch_queue.running_threads, -1) == 1 { // Returns old value for fuck sake
        SetEvent(dispatch_queue.progress_finished);
    }

    // @Todo,@Cleanup: use engine primitives
    // ExitThread(0);
    _endthreadex(0);
}

shutdown_dispatch_looper :: (thread_looper : ExecutionContext) -> *DispatchContext {
    resume_context := switch_dispatch_thread_execution_context_explicit(activate = thread_looper, reason = .stop);

    // @Todo: validate
    return unpack_dispatch_context(resume_context);
}

shutdown_context :: inline (activate : ExecutionContext, looper_context : *DispatchContext) {
    thread_set_context(
        activate       = activate,
        resume_context = create_resume_context(
            resume_data    = looper_context,
            resume_payload = cast(u64) DispatchResumeReason.stop
        )
    );
}

_endthreadex :: (retval : u32) #foreign;

SetEvent :: (hEvent: Windows.HANDLE) -> bool #foreign kernel32;
SetThreadAffinityMask :: (h: Windows.HANDLE, mask: s64) -> Windows.BOOL #foreign;
ExitThread :: (exit_code: u32) -> void #foreign kernel32;

Basic   :: #import "Basic";
Thread  :: #import "Thread";
Windows :: #import "Windows";

#import "logger";

#import "core/atomic";
#import "core/basic";
#import "core/concurrency/concurrent_queue";
#import "core/concurrency/thread";

operator - :: Basic.operator -;

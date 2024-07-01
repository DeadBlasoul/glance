#scope_export

DispatchBarrier :: struct(count : s64 = 0) {
    lock_count : s64;

    #if count == {
        case 0; lock_array : []DispatchSavepoint;
                swap_array : []DispatchSavepoint;

        case;   lock_array : [count - 1]DispatchSavepoint;
    }
}

arrive_and_wait :: (barrier : *DispatchBarrier) {
    count      := barrier.lock_array.count;
    lock_count := Default_Atomics.atomic_add(*barrier.lock_count, 1);  //< Returns old value.

    //
    // Barrier block path.
    //

    if lock_count != count {
        dispatch_thread_context := get_dispatch_thread_context();

        resume_context := switch_dispatch_thread_execution_context_implicit(
            savepoint = *barrier.lock_array[lock_count],
            activate  = query_dispatch_looper(dispatch_thread_context),
            reason    = .resumed,
            dispatch_thread_context
        );
        assert(unpack_reason(resume_context) == .resumed);

        return;
    }

    //
    // Barrier release path.
    //

    // Wait for all ongoing suspends.
    for ix : 0..barrier.lock_array.count - 1 {
        while load(*barrier.lock_array[ix], memory_order = .acquire) == .invalid memory_fence_store();
    }

    // Save lock array before cleaning it. Otherwise, we might get in data race when barrier releasing collides with the next round locks.
    lock_array : [barrier.count - 1]DispatchSavepoint = barrier.lock_array;

    memset(barrier.lock_array.data, 0, size_of(DispatchSavepoint) * barrier.lock_array.count);
    store(*barrier.lock_count, 0, memory_order = .release);

    // At this point barrier is set and done. We only need to resume suspended contexts.
    dispatch_thread_context   := get_dispatch_thread_context();
    dispatch_queue            := dispatch_thread_context.dispatch_queue;
    dispatch_queue_dispatcher := dispatch_thread_context.dispatch_queue_dispatcher;

    for locked_context : lock_array {
        while !try_enqueue(*dispatch_queue.work_queue, dispatch_queue_dispatcher, create_dispatch_work_item(consume_dispatch_from_immediate(locked_context))) {
            continue;
        }

        // @Todo: Use engine primitives.
        SetEvent(dispatch_queue.progress);
    }
}

#scope_file

Default_Atomics :: #import "Atomics";

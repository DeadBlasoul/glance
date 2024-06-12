DispatchWorkItem :: union {
    /*

    The main goal for this type is to tightly pack 2 distinguished message types whether we want to
    send a pair of a task routine and its context, or to send a suspended context.

    Since `dispatched_context` has strong restrictions on its alignment and we can force some of these
    onto `dispatched_task_context`, we could take the last 3 bits (alignment by 8) to specify the type
    of dispatched work. Otherwise, it will lead us to wasting space for `type` and maybe some padding.

    In the end it's just bit-mask operations, so nothing to worry about.

    @Warning:
        The fields of this union and inner structs are not meant to be accessed directly.
        Use getters provided by this file.

    */

    // Takes the last 3 bits of the first field.
    type : DispatchWorkItemType;

    using dispatched_task : struct {
        dispatched_task_context : *void;  // Must be aligned by 8
        dispatched_task_routine : (*void) -> ();
    };

    dispatched_context : ExecutionContext; // Must be aligned by 8
}
#assert size_of(DispatchWorkItem) == 16;

DispatchWorkItemType :: enum {
    dispatched_task;
    dispatched_context;
}
dispatch_work_item_type_mask :: 0b111;

create_dispatch_work_item :: inline (task_context : *T, task_routine : (*$T) -> ()) -> DispatchWorkItem {
    assert(task_context & dispatch_work_item_type_mask == null, "The provided task context pointer must be aligned by 8: %", task_context);

    work := DispatchWorkItem.{
        dispatched_task_context = cast(*void)         task_context,
        dispatched_task_routine = cast((*void) -> ()) task_routine,
    };
    work.type |= .dispatched_task;

    return work;
}

create_dispatch_work_item :: inline (suspended_context : ExecutionContext) -> DispatchWorkItem {
    assert(suspended_context & dispatch_work_item_type_mask == null, "The provided suspended context pointer must be aligned by 8: %", suspended_context);

    work := DispatchWorkItem.{
        dispatched_context = suspended_context,
    };
    work.type |= .dispatched_context;

    return work;
}

get_dispatch_work_item_type :: (work : DispatchWorkItem) -> DispatchWorkItemType #expand {
    return work.type & dispatch_work_item_type_mask;
}

unpack_as_dispatched_task :: (work : DispatchWorkItem) -> (task_context : *void, task_routine : (*void) -> ()) #expand {
    return
        work.dispatched_task_context & ~dispatch_work_item_type_mask,
        work.dispatched_task_routine;
}

unpack_as_dispatched_context :: (work : DispatchWorkItem) -> ExecutionContext #expand {
    return work.dispatched_context & ~dispatch_work_item_type_mask;
}

Dispatch :: enum s64 {
    invalid;
};

/// Serialization type for Dispatch. In order to make a dispatch, must be reactivated by consuming it with `consume_dispatch`.
/**
 *  @Discussion:
 *      The problem is to make sure that any serialized `Dispatch` object would be consumed (cleared with .invalid) right before dispatch.
 *      Otherwise it will leave a dangling reference where it hardly to identify it was intentional or caused by a bug.
 *
 *      The current solution is to introduce a special kind of dispatch objects that are impossible to dispatch without deserializing them.
 *
 *      Serialization is done by dispatching functions (see dispatch_thread.jai).
 */
DispatchSavepoint :: enum s64 {
    invalid;
};

consume_dispatch :: (dispatch_savepoint : *DispatchSavepoint) -> Dispatch #no_context {
    defer dispatch_savepoint.* = .invalid;
    return cast(Dispatch) dispatch_savepoint.*;
}

consume_dispatch_from_immediate :: (dispatch_savepoint : DispatchSavepoint) -> Dispatch #no_context {
    return cast(Dispatch) dispatch_savepoint;
}

serialize_dispatch :: (dispatch : Dispatch) -> DispatchSavepoint #no_context {
    return cast(DispatchSavepoint) dispatch;
}

restore_dispatch_memory_pointer :: inline (dispatch : Dispatch) -> *DispatchMemoryImage #no_context {
    return cast(*DispatchMemoryImage) (dispatch & ~(dispatch_memory_image_alignment - 1));
}

/// Dispatch fields without execution context.
DispatchAttributes :: enum_flags {
    none         :: 0;
    is_blockable :: 1;
};

DispatchContext :: struct {
    savepoint            : DispatchSavepoint;
    attributes           : DispatchAttributes;
    requested_stack_size : s64;
    effective_stack_size : s64;
    allocation_slot      : DispatchMemoryAllocationSlot;
}

dispatch_context_alignment    :: 64;
dispatch_context_aligned_size :: ~(dispatch_context_alignment - 1) & (size_of(DispatchContext) + dispatch_context_alignment - 1);

#assert is_power_of_2(dispatch_context_alignment);
#assert size_of(DispatchContext) <= dispatch_context_aligned_size;

DispatchMemoryImage :: struct {
    /// Memory of the stack passed to the dispatch (will be the initial RSP).
    /**
     * @Note: The commited size of the stack might be less than the reserved size of the memory.
     *        To retrieve operational stack size use `dispatch_context` field.
     */
    stack_area       : [dispatch_memory_image_target_size - dispatch_context_aligned_size]u8;

    /// Core runtime information of the ongoing dispatch.
    dispatch_context : DispatchContext #align dispatch_context_alignment;

    /// Tail guard pages. Always present. The size is determined by the OS.
    #place stack_area; guard_area : [1]u8;
}

dispatch_memory_image_target_size :: 1 * 1024 * 1024; // 1 Mb
dispatch_memory_image_alignment   :: 1 * 1024 * 1024; // 1 Mb

#assert is_power_of_2(dispatch_memory_image_target_size);
#assert size_of(DispatchMemoryImage) == dispatch_memory_image_target_size;

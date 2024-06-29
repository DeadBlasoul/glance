DispatchLooperAllocator :: struct(
    dispatch_stack_memory_size : s64,

    /// Number of stacks per thread.
    /**
     * Each thread gets its own shared bunch of images for dispatches. This allows for gradual scaling in multithreading systems.
     * In OOM cases, the remaining free stacks will be shared between starving threads.
     */
    dispatch_memory_images_per_thread : s64
) {
    #assert is_power_of_2(dispatch_stack_memory_size);
    #assert dispatch_stack_memory_size <= size_of(DispatchMemoryImage);

    memory_arena          : []DispatchMemoryImage;
    memory_control_blocks : []MemoryControlBlock;

    MemoryControlBlock :: struct {
        #assert 0 < dispatch_memory_images_per_thread && dispatch_memory_images_per_thread <= max_threads_per_span;

        /// Set bit - deallocated, unset bit - allocated.
        allocation_map : s64 = -1 #align cache_line_size;
        max_threads_per_span :: 64;
    }
}

/// [0:6) bits - span index; [6:64) packed allocation map address.
DispatchMemoryAllocationSlot :: enum s64 { system; };

create_dispatch_looper_allocator :: (allocator : *DispatchLooperAllocator, threads_count : s64) {
    //
    // Allocate control blocks.
    //

    Basic.array_resize(*allocator.memory_control_blocks, threads_count);

    //
    // Reserve memory arena with required alignment.
    //

    #assert is_power_of_2(dispatch_memory_image_alignment);
    #assert dispatch_memory_image_target_size == dispatch_memory_image_alignment "DispatchMemoryImage base must be discoverable from any pointer within it";

    memory_arena_size := size_of(DispatchMemoryImage) * allocator.dispatch_memory_images_per_thread * threads_count;
    memory_arena_base := os_allocate_memory(
        base            = null,
        size            = memory_arena_size,
        alignment       = dispatch_memory_image_alignment,
        protection      = .rw,
        allocation_type = .reserve
    );

    assert(memory_arena_base.data != null, "os_allocate_memory failed");

    allocator.memory_arena = .{
        count = allocator.dispatch_memory_images_per_thread * threads_count,
        data  = xx memory_arena_base.data,
    };

    //
    // Map & initialize memory arena.
    //

    for *image, image_index : allocator.memory_arena {
        operational_stack_area_size :: #run Basic.min(allocator.dispatch_stack_memory_size, image.stack_area.count);

        // Commit dispatch context.
        os_allocate_memory(
            base            = *image.dispatch_context, //< Will round down to beginning of the page where allocation is being on (at least, on Windows).
            size            = size_of(DispatchContext),
            protection      = .rw,
            allocation_type = .commit
        );

        // Commit operational part of the stack area.
        os_allocate_memory(
            base            = image.stack_area.data + image.stack_area.count - operational_stack_area_size,
            size            = operational_stack_area_size,
            protection      = .rw,
            allocation_type = .commit
        );

        // Map the rest of the stack area as "no access". Guard area must be set as the last one to make it always existing
        // even if `operational_stack_area_size` is equal to the size of stack area.
        success, effective_guard_area := os_protect_memory(
            base       = image.guard_area.data,
            size       = image.stack_area.count - operational_stack_area_size,
            protection = .no_access
        );

        assert(success, "Memory protection failed: [TODO: SYSTEM ERROR]");
        assert(effective_guard_area.count > 0, "Memory protection returned empty area");

        effective_stack_area_size := image.stack_area.count - effective_guard_area.count;

        //
        // Setup dispatch context.
        //

        memory_control_block_index       := image_index / allocator.dispatch_memory_images_per_thread;
        memory_control_block             := *allocator.memory_control_blocks[memory_control_block_index];
        image_index_within_control_block := image_index % allocator.dispatch_memory_images_per_thread;

        image.dispatch_context = .{
            savepoint            = .invalid,
            attributes           = .none,
            requested_stack_size = allocator.dispatch_stack_memory_size,
            effective_stack_size = effective_stack_area_size,
            allocation_slot      = pack_allocation_slot(*memory_control_block.allocation_map, image_index_within_control_block),
        };
    }
}

destroy_dispatch_looper_allocator :: (allocator : *DispatchLooperAllocator) {
    //
    // Verify that allocator has no allocated memory.
    //

    has_allocated_memory := false;
    for *memory_control_block, index : allocator.memory_control_blocks {
        if memory_control_block.allocation_map == -1 then continue;

        has_allocated_memory = true;

        builder : Basic.String_Builder;
        Basic.print_to_builder(*builder, "Dispatch allocator [%] has allocated memory in block %", allocator, index);

        for memory_image_index : 0..allocator.dispatch_memory_images_per_thread - 1 {
            if bit_test(memory_control_block.allocation_map, memory_image_index) == false {
                dispatch_memory := *allocator.memory_arena[index * allocator.dispatch_memory_images_per_thread + memory_image_index];
                Basic.print_to_builder(*builder, "\n>>> %", dispatch_memory);
            }
        }

        Log.error("%", Basic.builder_to_string(*builder));
    }
    assert(!has_allocated_memory, "Dispatch allocator [%] has allocated memory", allocator);

    //
    // Gracefully destroy managed data.
    //

    for *image : allocator.memory_arena {
        dispatch := consume_dispatch(*image.dispatch_context.savepoint);
        if dispatch != .invalid then request_dispatch_stop(dispatch);
    }

    Basic.array_reset(*allocator.memory_control_blocks);

    memory_arena_size := size_of(DispatchMemoryImage) * allocator.memory_arena.count;
    memory_arena_base := cast(*u8) allocator.memory_arena.data;

    os_release_memory(memory_arena_base, memory_arena_size);
    allocator.memory_arena = .[];
}

create_dispatch_looper :: (allocator : *DispatchLooperAllocator, dispatch_thread_index : s64) -> Dispatch {
    dispatch_memory := allocate_dispatch_memory(allocator, dispatch_thread_index);

    dispatch := consume_dispatch(*dispatch_memory.dispatch_context.savepoint);
    if dispatch != .invalid {
        // The looper is already started, no startup is required.
        return dispatch;
    }

    return cast(Dispatch) thread_create_execution_context(dispatch_memory.stack_area, *dispatch_memory.dispatch_context, xx dispatch_looper_starter);
}

release_dispatch_looper :: (dispatch_looper : Dispatch) {
    dispatch_memory := restore_dispatch_memory_pointer(dispatch_looper);

    if dispatch_memory.dispatch_context.allocation_slot == {
        // Dispatch memory was allocated from an arena.
        case; {
            allocation_map, image_index := unpack_allocation_slot(dispatch_memory.dispatch_context.allocation_slot);
            atomic_bit_set(allocation_map, image_index);

            dispatch_memory.dispatch_context.savepoint = dispatch_looper;
        }

        // Dispatch memory was allocated by the OS.
        case .system; {
            request_dispatch_stop(dispatch_looper);
            os_release_memory(dispatch_memory);
        }
    }
}

#scope_file

shutdown_dispatch_looper :: (dispatch_looper : Dispatch) {
    dispatch_memory := restore_dispatch_memory_pointer(dispatch_looper);

    request_dispatch_stop(dispatch_looper);

    if dispatch_memory.dispatch_context.allocation_slot == {
        // Dispatch memory was allocated from an arena.
        case; {
            allocation_map, image_index := unpack_allocation_slot(dispatch_memory.dispatch_context.allocation_slot);
            atomic_bit_set(allocation_map, image_index);
        }

        // Dispatch memory was allocated by the OS.
        case .system; {
            os_release_memory(dispatch_memory);
        }
    }
}

request_dispatch_stop :: (dispatch : Dispatch) {
    resume_context  := switch_dispatch_thread_execution_context_explicit(activate = dispatch, reason = .stop);
    assert(unpack_reason(resume_context) == .resumed);
}

allocate_dispatch_memory :: (using allocator : *DispatchLooperAllocator, dispatch_thread_index : s64) -> *DispatchMemoryImage {
    //
    // Allocte memory from the arena.
    //

    threads_count := memory_control_blocks.count;

    // Iterate over each memory control block starting from the one corresponding to the index of desired dispatch thread.
    for forward_thread_index : dispatch_thread_index..dispatch_thread_index + threads_count - 1 {
        memory_control_block_index := forward_thread_index % threads_count;
        allocation_map             := *memory_control_blocks[memory_control_block_index].allocation_map;

        while allocating_within_current_control_block := true {
            // candidate_image_index := trailing_zeroes_count(load(allocation_map, memory_order = .acquire));
            candidate_image_index := trailing_zeroes_count(allocation_map);

            // Check for out-of-memory within current control block.
            if candidate_image_index >= dispatch_memory_images_per_thread {
                break allocating_within_current_control_block;
            }

            // Attempt to commit memory allocation.
            if atomic_bit_test_and_reset(allocation_map, candidate_image_index) == false {
                continue allocating_within_current_control_block;
            }

            memory := *memory_arena[memory_control_block_index * dispatch_memory_images_per_thread + candidate_image_index];
            Log.debug("New memory block is just allocated: %", memory);

            // Allocation is successful, return commited memory.
            return memory;
        }
    }

    //
    // Allocate memory by the OS.
    //

    memory_base := os_allocate_memory(
        base            = null,
        size            = size_of(DispatchMemoryImage),
        alignment       = dispatch_memory_image_alignment,
        protection      = .rw,
        allocation_type = .reserve
    );

    assert(memory_base.data != null);

    //
    // Map memory.
    //

    image := cast(*DispatchMemoryImage) memory_base.data;

    operational_stack_area_size :: #run Basic.min(allocator.dispatch_stack_memory_size, image.stack_area.count);

    // Commit dispatch context.
    os_allocate_memory(
        base            = *image.dispatch_context, //< Will round down to beginning of the page where allocation is being on (at least, on Windows).
        size            = size_of(DispatchContext),
        protection      = .rw,
        allocation_type = .commit
    );

    // Commit operational part of the stack area.
    os_allocate_memory(
        base            = image.stack_area.data + image.stack_area.count - operational_stack_area_size,
        size            = operational_stack_area_size,
        protection      = .rw,
        allocation_type = .commit
    );

    // Map the rest of the stack area as "no access". Guard area must be set as the last one to make it always existing
    // even if `operational_stack_area_size` is equal to the size of stack area.
    success, effective_guard_area := os_protect_memory(
        base       = image.guard_area.data,
        size       = image.stack_area.count - operational_stack_area_size,
        protection = .no_access
    );

    todo("Add support for system errors");

    assert(success, "Memory protection failed: [TODO: SYSTEM ERROR]");
    assert(effective_guard_area.count > 0, "Memory protection returned empty area");

    effective_stack_area_size := image.stack_area.count - effective_guard_area.count;

    //
    // Initialize memory.
    //

    image.dispatch_context = .{
        savepoint            = .invalid,
        attributes           = .none,
        requested_stack_size = allocator.dispatch_stack_memory_size,
        effective_stack_size = effective_stack_area_size,
        allocation_slot      = .system,
    };

    return image;
}

release_dispatch_memory :: (image : *DispatchMemoryImage) {
    allocation_slot := image.dispatch_context.allocation_slot;

    if allocation_slot == .system {
        os_release_virtual_memory(image, size_of(DispatchMemoryImage));
    } else {
        allocation_map, image_index := unpack_allocation_slot(allocation_slot);
        atomic_bit_set(allocation_map, image_index);
    }
}

pack_allocation_slot :: inline (allocation_map : *s64, span_index : s64) -> DispatchMemoryAllocationSlot #no_context {
    slot := (cast(s64) allocation_map) ^ span_index;
    return xx slot;
}

unpack_allocation_slot :: inline (slot : DispatchMemoryAllocationSlot) -> (allocation_map : *s64, span_index : s64) #no_context {
    slot_value     := cast(s64) slot;
    allocation_map := (slot_value >> 6) << 6;
    span_index     := slot_value ^ allocation_map;
    return cast(*s64) allocation_map, span_index;
}

#scope_file

Log :: TaggedLogger("Looper Allocator");

Basic :: #import "Basic";

#import "core/compile_time_support";
#import "logger";

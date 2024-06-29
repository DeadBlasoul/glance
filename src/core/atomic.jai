/**
 * @Important:
 *  Jai does not support compiler barries (at the moment of writinig this code), so most of this
 *  is more likely for the reader, rather than for the compiler. We may *believe* that certain
 *  intrinsics and assembly inlines will not be reordered or optimized, but there is no guarantee for that yet.
 */

/// Memory order for store & load operations.
MemoryOrder :: enum_flags {
    relaxed;
    acquire;
    release;
    sequence_cast :: acquire | release;

    memory_order_relaxed       :: relaxed;
    memory_order_acquire       :: acquire;
    memory_order_release       :: release;
    memory_order_sequence_cast :: sequence_cast;
}

#if CPU == .X64 {
    cache_line_size :: 64;

    memory_fence_load :: () #expand {
        #asm {lfence;}
    }

    memory_fence_store :: () #expand {
        #asm {sfence;}
    }

    memory_fence_modify :: () #expand {
        #asm {mfence;}
    }

    memory_fence_relax :: () #expand {
        #asm {pause;}
    }

    load :: inline (source: *$T, $memory_order: MemoryOrder) -> T #no_context {
        #if memory_order == {
            case .memory_order_relaxed;
                return source.*;

            case .memory_order_acquire;
                return source.*;

            case; #assert false, #run Basic.sprint("memory order `%` cannot be applied to a load operation", order);
        }
    }

    store :: inline (destination: *$T, value: T, $memory_order: MemoryOrder) #no_context {
        #if memory_order == {
            case .memory_order_relaxed;
                destination.* = value;

            case .memory_order_release;
                destination.* = value;

            case; #assert false, #run Basic.sprint("memory order `%` cannot be applied to a store operation", order);
        }
    }
}

spin :: () #expand {
    memory_fence_relax();
}

compare_and_swap :: (destination: *$T, old_value: T, new_value: T, $memory_order: MemoryOrder) -> (actual_old_value: T) #expand {
    Default_Atomic :: #import "Atomics";
    _, actual_old_value := Default_Atomic.compare_and_swap(destination, old_value, new_value);
    return actual_old_value;
}

atomic_bit_set :: inline (bit_base : *$T, $$bit_offset : s64) #no_context #modify { return is_integer_type(T); } {
    #asm {
        lock_bts [bit_base], bit_offset;
    }
}

atomic_bit_reset :: inline(bit_base : *$T, $$bit_offset : s64) #no_context #modify { return is_integer_type(T); } {
    #asm {
        lock_btr [bit_base], bit_offset;
    }
}

atomic_bit_test_and_set :: inline (bit_base : *$T, $$bit_offset : s64) -> bool #no_context #modify { return is_integer_type(T); } {
    previous : bool = ---;
    #asm {
        lock_bts [bit_base], bit_offset;
        setc previous;
    }
    return previous;
}

atomic_bit_test_and_reset :: inline (bit_base : *$T, $$bit_offset : s64) -> bool #no_context #modify { return is_integer_type(T); } {
    Basic :: #import "Basic";
    #run Basic.print("COMPILER BUG WORKAROUND: atomic_bit_test_and_reset is being compiled in an inefficient way, because without explicit xor it inserts another xor right after lock_btr which resets CF");

    previous : bool = ---;
    #asm {
        xor previous, previous;
        lock_btr [bit_base], bit_offset;
        setc previous;
    }
    return previous;
}

#scope_file

#import "core/type_traits";

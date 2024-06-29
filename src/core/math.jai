is_power_of_2 :: (x : $T) -> bool #no_context {
    return x > 0 && (x & (x - 1)) == 0;
}

trailing_zeroes_count :: inline (v : $T) -> s64 #no_context #modify { return is_integer_type(T); } {
    #if CPU == {
        case .X64; {
            count : s64;
            #asm { tzcnt count, v; };
            return count;
        }
    }
}

trailing_zeroes_count :: inline (v : *$T) -> s64 #no_context #modify { return is_integer_type(T); } {
    #if CPU == {
        case .X64; {
            count : s64;
            #asm { tzcnt count, [v]; };
            return count;
        }
    }
}

bit_test :: inline (bit_base : $T, bit_offset : s64) -> bool #no_context #modify { return is_integer_type(T); } {
    return cast(bool) (bit_base & (1 << bit_offset));
}

#scope_file

#import "core/type_traits";

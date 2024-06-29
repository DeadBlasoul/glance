//! Returns a new string with "\0" at the end of the string.
/**
 * If allocation failed, empty C-style string is returned.
 */
convert_to_c_style_string :: (s : string, allocator : Allocator = .{}) -> string {
    result : string = ---;

    result.count = s.count + 1;
    result.data  = Basic.alloc(result.count);
    if !result.data {
        return "\0";
    }

    memcpy(result.data, s.data, s.count);
    result[s.count] = #char "\0";

    return result;
}

to_temp_c_string :: (s: string) -> *u8 {
    result : *u8 = Basic.alloc(s.count + 1,, allocator = Basic.temporary_allocator);

    memcpy(result, s.data, s.count);
    result[s.count] = #char "\0";

    return result;
}

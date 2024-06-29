is_integer_type :: (T: Type) -> bool #compile_time {
    ti := cast(*Type_Info) T;
    return ti.type == .INTEGER;
}

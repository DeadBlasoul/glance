as_stack_aligned :: (memory : []u8, $alignment : s64) -> (stack : []u8) {
    stack       := memory;
    stack.count  = ((stack.data + stack.count) & -alignment) - stack.data;
    return stack;
}

allocate_on_stack_aligned :: (stack : *[]u8, $T: Type, $alignment : s64) -> *T {
    allocated   := (stack.data + stack.count - size_of(T)) & -alignment;
    stack.count  = allocated - stack.data;
    return cast(*T) allocated;
}

allocate_on_stack_aligned :: (stack : *[]u8, $size : s64, $alignment : s64) -> *void {
    allocated   := (stack.data + stack.count - size) & -alignment;
    stack.count  = allocated - stack.data;
    return cast(*void) allocated;
}

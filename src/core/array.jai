
array_reset_keeping_memory :: inline (array : *[..]$T, $$on_each_deleted_item : (item : *T) -> () = null) {
    #if is_constant(on_each_deleted_item) && on_each_deleted_item {
        for < *item : array.* {
            on_each_deleted_item(item);
        }
    } else if on_each_deleted_item {
        for < *item : array.* {
            on_each_deleted_item(item);
        }
    }
    Basic.array_reset_keeping_memory(array);
}

array_reset_keeping_memory :: (array : *[..]$T, $on_each_deleted_item : Code = null) #expand {
    #if on_each_deleted_item {
        for < *item : array.* {
            #insert,scope() on_each_deleted_item;
        }
    }
    Basic.array_reset_keeping_memory(array);
}

DispatchSemaphore :: struct {
    owner      : *DispatchContext;
}

acquire_lock :: (DispatchSemaphore)
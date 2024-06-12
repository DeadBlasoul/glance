Thread :: struct {
    // workspace : Compiler.Workspace;

    // using specific : ThreadOsSpecific;
}

ThreadIndex  :: s64;
ThreadResult :: s32; // @Cleanup: must be defined in platform implementation.
ThreadProc   :: #type (*Thread) -> ThreadResult;

create_thread  :: () {}
destroy_thread :: () {}

start_thread  :: () {}
join_thread   :: () {}
detach_thread :: () {}

#if OS == {
    case .WINDOWS; {
        #if CPU == {
            case .X64; #load "thread_windows_x64.jai";
            case;      #assert false, #run Basic.sprint("% is not supported for %", CPU, OS);
        }
    }

    case; #assert false, #run Basic.sprint("% is not supported", OS);
}
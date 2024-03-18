#if OS == .WINDOWS {
    #if CPU == .X64 {
        #load "execution_context_windows_x64.jai";
    } else {
        #assert false, #run Basic.sprint("% is not supported for %", CPU, OS);
    }
} else {
    #assert false, #run Basic.sprint("% is not supported", OS);
}

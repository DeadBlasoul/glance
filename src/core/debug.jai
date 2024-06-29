get_cpu_clock_count :: inline () -> u64 #c_call {
    result: u64 = ---;
    #asm {
        lo: gpr === a;
        hi: gpr === d;

        rdtsc hi, lo;

        shl hi, 32;
        or  lo, hi;
        mov result, lo;
    }
    return result;
}

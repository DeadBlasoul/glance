BuildConfig :: struct {
    project_name : string;

    assertions : enum u8 {
        DISABLED;
        ENABLED;
    } = .ENABLED;

    cpu : enum u8 {
        DEBUG;
        RELEASE;
    } = .DEBUG;

    gpu : enum u8 {
        DEBUG;
        RELEASE;
    } = .DEBUG;
};

BUILD_CONFIG, GPU_DEBUG, RELEASE_BUILD :: #run -> (BuildConfig, is_gpu_debug: bool, is_release_build: bool) {
    build_config_pointer : *BuildConfig = Compiler.get_build_options().user_data_pointer;
    using build_config := ifx build_config_pointer then build_config_pointer.* else .{};

    return
        build_config,
        is_gpu_debug     = (gpu == .DEBUG),
        is_release_build = (cpu == .RELEASE && gpu == .RELEASE);
};

#scope_file

Compiler :: #import "Compiler";

RuntimeShadersRecompiler :: struct {
    watcher : File_Watcher(RuntimeShadersRecompiler);

    compiler : shaderc_compiler_t;

    worker_thread : Thread.Thread;
    keep_running  : bool = true;

    //! A pool of the updated shaders.
    /**
     * After the processing is done, must be resetted by `consume_changed_shaders_pool`.
     */
    changed_shaders_pool : [..]ChangedShader;
    changed_shaders_lock : Thread.Mutex;

    //! Indicator of non-emptiness of changed shaders pool.
    /**
     * We keep it as a separate variable to make interrupt of rendering thread as low, as possible.
     * Without that, we can simply check `changed_shaders_pool.count`.
     */
    has_changed_shaders  : bool;
}

ChangedShader :: struct {
    path          : string;
    shader_binary : []u8;
}

setup_shaders_recompiler :: inline (using recompiler : *RuntimeShadersRecompiler) {
    compiler = shaderc_compiler_initialize();
    Basic.assert(compiler != null);

    succeeded := init(*watcher, on_shader_source_modified, recompiler, events_to_watch = .MODIFIED);
    Basic.assert(succeeded);

    succeeded = add_directories(*watcher, SHADERS_SOURCE_PATH);
    Basic.assert(succeeded);

    succeeded = Thread.thread_init(*worker_thread, shaders_recompiler_worker_procedure);
    Basic.assert(succeeded);

    worker_thread.data = recompiler;
    Thread.init(*changed_shaders_lock);
    Thread.thread_start(*worker_thread);
}

consume_changed_shaders_pool :: inline (using recompiler : *RuntimeShadersRecompiler) {
    array_reset_keeping_memory(*changed_shaders_pool, on_each_deleted_item = #code {
        Basic.free(item.path);
        Basic.array_free(item.shader_binary);
    });
    has_changed_shaders = false;
}

destroy_shaders_recompiler :: inline (using recompiler : *RuntimeShadersRecompiler) {
    keep_running = false;
    Thread.thread_deinit(*worker_thread);
    Thread.destroy(*changed_shaders_lock);

    consume_changed_shaders_pool(recompiler);
    Basic.array_free(changed_shaders_pool);

    deinit(*watcher);

    shaderc_compiler_release(compiler);
}

#scope_file

// @Cleanup: local imports are not that good??
Basic      :: #import "Basic";
              #import "File_Watcher";
String     :: #import "String";

#load "shaderc/shaderc.jai";

// @Cleanup: hackish, should be a separate module `core`
#load "../core/array.jai";

SHADERS_SOURCE_PATH :: "./src/shaders";

shaders_recompiler_worker_procedure :: (thread: *Thread.Thread) -> s64 {
    sleep :: (seconds : float64) { Basic.sleep_milliseconds(cast(s32) seconds * 1000); }

    recompiler : *RuntimeShadersRecompiler = thread.data;
    while recompiler.keep_running {
        changed      : bool    = ---;
        needs_wait   : bool    = ---;
        wait_seconds : float64 = ---;
        {
            Thread.lock(*recompiler.changed_shaders_lock); defer Thread.unlock(*recompiler.changed_shaders_lock);
            changed, needs_wait, wait_seconds = process_changes(*recompiler.watcher);

            recompiler.has_changed_shaders |= recompiler.changed_shaders_pool.count > 0;
        }

        Basic.reset_temporary_storage();
        if needs_wait sleep(wait_seconds);
    }

    return 0;
}

on_shader_source_modified :: (watcher : *File_Watcher(RuntimeShadersRecompiler), change: *File_Change, recompiler: *RuntimeShadersRecompiler) {
    Basic.assert(change.events & .MODIFIED != 0);

    // @TODO: recompile shader
    // @TODO: save binary
    // @TODO: add shader binary instead of path to the shader

    for changed_shader : recompiler.changed_shaders_pool {
        if changed_shader.path == change.full_path {
            return;
        }
    }

    success, shader_binary := compile_shader_source_file(recompiler, change.full_path);
    if success {
        Basic.print("[---] lol\n");
        Basic.array_add(*recompiler.changed_shaders_pool, .{
            path          = Basic.copy_string(change.full_path),
            shader_binary = shader_binary,
        });
    } else {
        Basic.array_free(shader_binary);
    }
}

compile_shader_source_file :: (using recompiler: *RuntimeShadersRecompiler, shader_path : string) -> (success : bool #must, compiled_shader_binary : []u8 #must) {
    text, success := File.read_entire_file(shader_path);
    defer Basic.free(text);
    Basic.assert(success);

    compile_options := shaderc_compile_options_initialize();
    defer shaderc_compile_options_release(compile_options);

    SPIRV_VERSION : shaderc_spirv_version : .shaderc_spirv_version_1_6;

    shaderc_compile_options_set_source_language   (compile_options, .shaderc_source_language_glsl);
    shaderc_compile_options_set_optimization_level(compile_options, .shaderc_optimization_level_performance);
    shaderc_compile_options_set_target_env        (compile_options, .shaderc_target_env_vulkan, xx SPIRV_VERSION); // @TODO: use version from the instance instead
    shaderc_compile_options_set_invert_y          (compile_options, enable = true);

    shader_kind : shaderc_shader_kind = ifx String.ends_with(shader_path, ".vert") then .shaderc_glsl_vertex_shader else .shaderc_glsl_fragment_shader;
    compilation_result := shaderc_compile_into_spv(
        compiler,
        xx text.data,
        xx text.count,
        shader_kind,
        input_file_name    = xx to_temp_c_string(shader_path),  // @TODO: we need a correct -string
        entry_point_name   = xx "main\0".data,
        additional_options = compile_options
    );
    defer shaderc_result_release(compilation_result);

    Basic.assert(compilation_result != null); // Insufficient memory?

    compilation_status := shaderc_result_get_compilation_status(compilation_result);
    error_messages     := shaderc_result_get_error_message(compilation_result);

    if compilation_status != .shaderc_compilation_status_success {
        // TODO: check verbosity
        report : string = ---;
        report.data  = xx error_messages;
        report.count = c_style_strlen(xx error_messages);
        Basic.print("[---] Compilation of '%' failed:\n%\n", shader_path, report);
    }

    if compilation_status != .shaderc_compilation_status_success {
        return success = false, compiled_shader_binary = .[];
    }

    shader_binary : [..]u8;
    {
        shader_binary_length : s64 = xx shaderc_result_get_length(compilation_result);
        shader_bytes         : *s8 = shaderc_result_get_bytes(compilation_result);

        Basic.array_resize(*shader_binary, shader_binary_length);
        memcpy(shader_binary.data, shader_bytes, shader_binary_length);
    }

    // @Cleanup
    executable_path    := System.get_path_of_running_executable();
    bin_path           := String.slice(executable_path, 0, String.find_index_from_right(executable_path, #char "/"));
    shader_filename    := String.slice(shader_path, String.find_index_from_right(shader_path, #char "/") + 1, shader_path.count);
    shader_output_path := Basic.sprint("%/shaders/%.spv", bin_path, shader_filename);

    defer Basic.free(shader_output_path);

    Basic.print("[---] opening file to write: '%', origin shader path: '%'\n", shader_output_path, shader_path);
    output_file, opened := File.file_open(shader_output_path, for_writing = true, keep_existing_content = false); defer File.file_close(*output_file);
    {
        Basic.assert(opened);
        File.file_write(*output_file, shader_binary.data, shader_binary.count);
    }

    return success = true, shader_binary;
}

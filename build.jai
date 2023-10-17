#import "Basic";
#import "Compiler";
#import "String";
#import "File";
#import "Hash_Table";
#import "Process";
#import "File_Utilities";

#load "src/build_config.jai";

#run {
    PROJECT_NAME :: "vk_renderer";

    // Disable writing executable file for the current file since it acts only as a build config.
    set_build_options_dc(.{
        do_output = false,
    });

    workspace    := compiler_create_workspace(PROJECT_NAME);
    options      := get_build_options();
    build_config := BuildConfig.{
        project_name = PROJECT_NAME,
    };

    //
    // Parse command line arguments
    //
    run_after_building : bool = ---;
    build_shaders      : bool = false;
    {
        command_line_options : Table(string, string);
        parse_command_line_arguments(options.compile_time_command_line, *command_line_options);

        run_after_building = table_contains(*command_line_options, "run");

        if table_contains(*command_line_options, "release") {
            build_config.assertions = .DISABLED;
            build_config.cpu        = .RELEASE;
            build_config.gpu        = .RELEASE;
        }

        if table_contains(*command_line_options, "shaders") {
            build_shaders = true;
        }


        value, found := table_find(*command_line_options, "-assertions");
        if found {
            if equal_nocase(value, "enabled") {
                build_config.assertions = .ENABLED;
            } else {
                build_config.assertions = .DISABLED;
            }
        }

        value, found = table_find(*command_line_options, "-cpu");
        if found {
            if equal_nocase(value, "release") {
                build_config.cpu = .RELEASE;
            } else {
                build_config.cpu = .DEBUG;
            }
        }

        value, found = table_find(*command_line_options, "-gpu");
        if found {
            if equal_nocase(value, "release") {
                build_config.gpu = .RELEASE;
            } else {
                build_config.gpu = .DEBUG;
            }
        }
    }

    //
    // Setup build options
    //
    project_dir      := current_source_file_dir();
    build_type_dir   := compose_appropriate_build_type_dir(*build_config);
    install_dir      := join(project_dir, "/bin", build_type_dir);
    intermediate_dir := join(project_dir, "/build", build_type_dir);
    {
        make_directory_if_it_does_not_exist(install_dir,      recursive = true);
        make_directory_if_it_does_not_exist(intermediate_dir, recursive = true);
    }

    //
    // Shaders
    //
    if build_shaders {
        enumerate_and_build_shaders(install_dir);
    }

    //
    // Shaderc
    //
    if build_config.gpu == .DEBUG {
        additional_linker_arguments : [..]string;
        array_resize(*additional_linker_arguments, options.additional_linker_arguments.count + 1);
        
        for argument, ix : options.additional_linker_arguments {
            additional_linker_arguments[ix] = argument;
        }
        
        additional_linker_arguments[options.additional_linker_arguments.count + 0] = "/LIBPATH:C:/VulkanSDK/1.3.250.0/Lib";
        
        options.additional_linker_arguments = additional_linker_arguments;
    }

    //
    // Additional modules dir
    //
    modules_paths: [..] string;
    array_add(*modules_paths, join(#filepath, "src/modules"));
    array_add(*modules_paths, ..options.import_path);
    options.import_path = modules_paths;

    set_optimization(
        *options,
        ifx build_config.cpu == .RELEASE then .VERY_OPTIMIZED else .DEBUG,
        build_config.cpu == .DEBUG
    );
    options.output_type            = .EXECUTABLE;
    options.output_executable_name = PROJECT_NAME;
    options.output_path            = install_dir;
    options.intermediate_path      = intermediate_dir;
    options.text_output_flags      = .OUTPUT_TIMING_INFO;
    options.user_data_pointer      = *build_config;
    options.user_data_pointer_size = size_of(type_of(build_config));
    
    set_build_options(options, workspace);

    //
    // Build & Run (if required)
    //
    if run_after_building {
        compiler_begin_intercept(workspace);

        add_build_file(join(project_dir, "/src/main.jai"), workspace);

        error_occured := false;
        while true {
            message := compiler_wait_for_message();
            if message.workspace != workspace continue;
            if message.kind == .COMPLETE break;

            if message.kind == .ERROR {
                error_occured = true;
                continue;
            }
        }

        compiler_end_intercept(workspace);
        if error_occured {
            return;
        }

        executable_file : string = ---;
        #if OS == .WINDOWS {
            executable_file = join(options.output_path, "/", options.output_executable_name, ".exe");
        } else {
            executable_file = join(options.output_path, "/", options.output_executable_name);
        }

        write_string("\n-------------------------------------------------------------------------\n\n");

        run_command(executable_file);
    } else {
        add_build_file(join(project_dir, "/src/main.jai"), workspace);
    }
}

#scope_file

current_source_file_dir :: () -> string {
    loc :: #location();

    filename_it := loc.fully_pathed_filename.data + loc.fully_pathed_filename.count - 1;

    while filename_it >= loc.fully_pathed_filename.data {
        if filename_it.* == {
            case #char "/";
                break;
            case #char "\\";
                break;
        }

        filename_it -= 1;
    }

    dir : string = ---;
    dir.data  = loc.fully_pathed_filename.data;
    dir.count = cast(s64) (filename_it - loc.fully_pathed_filename.data);

    return dir;
}

parse_command_line_arguments :: (options : []string, table : *Table(string, string)) {
    for option : options {
        _, key, value := split_from_left(option, #char "=");
        entry, _      := find_or_add(table, key);
        entry.*        = value;
    }
}

compose_appropriate_build_type_dir :: (using build_config : *BuildConfig) -> string {
    if assertions == .DISABLED && cpu == .RELEASE && gpu == .RELEASE {
        return "/release";
    }

    builder : String_Builder;
    print_to_builder(*builder, "/dev_cpu_%_gpu_%", cpu, gpu);

    result := builder_to_string(*builder);
    to_lower_in_place(result);

    return result;
}

get_filename_component :: (file_path : string) -> string {
    begin := find_index_from_right(file_path, #char "/");
    return slice(file_path, begin + 1, file_path.count - begin);
}

enumerate_and_build_shaders :: (install_dir : string) {
    SHADER_COMPILER :: "C:/VulkanSDK/1.3.250.0/Bin/glslangValidator.exe";

    make_directory_if_it_does_not_exist(sprint("%/%", install_dir, "shaders"), recursive = true);

    shaders := file_list("./src/shaders");
    for shader_path : shaders {
        print("[---] %\n", sprint("%/shaders/%.spv", install_dir, get_filename_component(shader_path)));

        if ends_with(shader_path, ".vert") {
            run_command(
                SHADER_COMPILER, shader_path,
                "--glsl-version", "460",
                "--target-env", "vulkan1.3",
                "--enhanced-msgs",
                "--spirv-val",
                "--entry-point", "main",
                "--invert-y",
                "-o", sprint("%/shaders/%.spv", install_dir, get_filename_component(shader_path))
            );
        } else {
            run_command(
                SHADER_COMPILER, shader_path,
                "--glsl-version", "460",
                "--target-env", "vulkan1.3",
                "--enhanced-msgs",
                "--spirv-val",
                "--entry-point", "main",
                "-o", sprint("%/shaders/%.spv", install_dir, get_filename_component(shader_path))
            );
        }
    }
}

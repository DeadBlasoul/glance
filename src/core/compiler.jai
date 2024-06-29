compile_assembly_library :: (libname : string, location := #caller_location) {
    // @Todo: debug/release?
    directory := path_strip_filename(location.fully_pathed_filename);
    run_command_checked(ml64, "/c", "/nologo", "/Cp", "/Zd", sprint("/Fo%/%.obj", directory, libname), sprint("%/%.asm", directory, libname));
    run_command_checked(lib, sprint("%/%.obj", directory, libname), sprint("/OUT:%/%.lib", directory, libname));
}

#scope_file

_, linker_path :: #run find_visual_studio_in_a_ridiculous_garbage_way();

ml64 :: #run sprint("%/ml64.exe", linker_path);
lib  :: #run sprint("%/lib.exe",  linker_path);


run_command_checked :: (command : ..string) {
    process_result, stdout, _ := run_command(..command, working_directory = #filepath, capture_and_return_output = true, print_captured_output = false);
    if process_result.exit_code {
        assert(false, sprint("Cannot execute command:\n%\n\n%", command, stdout));
    }
}

#import "Basic";
#import "Process";
#import "String";
#import "Windows_Resources";

main :: () {
    {
        using context.print_style.default_format_struct;

        use_long_form_if_more_than_this_many_members = 0;
        use_newlines_if_long_form                    = true;
    }

    #if !RELEASE_BUILD {
        Basic.print("BUILD_CONFIG : %\n", BUILD_CONFIG);
    }

    window_create_info : Window.WindowCreateInfo = .{
        jai_context = *context,
        title       = "vk_renderer",
        width       = 1920,
        height      = 1080,
    };

    window : Window.Window; defer Window.close_window(*window);
    Window.create_window(*window_create_info, *window);

    rendering_context : RenderingContext; defer destroy(*rendering_context);
    create(*rendering_context, with_window = *window);

    rendering_thread : Thread.Thread; defer Thread.thread_deinit(*rendering_thread);
    rendering_thread.data = *rendering_context;
    Thread.thread_init(*rendering_thread, rendering_thread_procedure);
    Thread.thread_start(*rendering_thread);

    Window.run(*window);
}

rendering_thread_procedure :: (thread : *Thread.Thread) -> s64 {
    using rendering_context : *RenderingContext = thread.data;
    while !window.is_closed {
        update(rendering_context);
    }

    return 0;
}

#load "core/code.jai";
#load "core/strings.jai";
#load "build_config.jai";
#load "rendering/rendering_context.jai";

Basic         :: #import "Basic";
Compiler      :: #import "Compiler";
String        :: #import "String";
File          :: #import "File";
Program_Print :: #import "Program_Print";
Math          :: #import "Math";
System        :: #import "System";
Thread        :: #import "Thread";
Window        :: #import "Window";

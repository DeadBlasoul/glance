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

    // Create Descriptor Pool
    // The example only requires a single combined image sampler descriptor for the font image and only uses one descriptor set (for that)
    // If you wish to load e.g. additional textures you may need to alter pools sizes.
    imgui_descriptor_pool : VkDescriptorPool = ---;
    {
        using rendering_context;

        pool_sizes := VkDescriptorPoolSize.[
            .{ .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1 },
        ];
        pool_info := VkDescriptorPoolCreateInfo.{
            flags         = .VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            maxSets       = 1,
            poolSizeCount = cast(u32) pool_sizes.count,
            pPoolSizes    = pool_sizes.data,
        };
        err := vkCreateDescriptorPool(device, *pool_info, null, *imgui_descriptor_pool);
        Basic.print("[---] err: %\n", err);
        // check_vk_result(err);
    }

    ImGui.CreateContext();               defer ImGui.DestroyContext();
    ImGui_ImplWin32_Init(window.handle); defer ImGui_ImplWin32_Shutdown();
    imgui_rendering_init_info := ImGui_ImplVulkan_InitInfo.{
        Instance              = rendering_context.instance,
        PhysicalDevice        = rendering_context.physical_device,
        Device                = rendering_context.device,
        QueueFamily           = rendering_context.family_index,
        PipelineCache         = VK_NULL_HANDLE,
        DescriptorPool        = imgui_descriptor_pool,
        Subpass               = 0,
        MinImageCount         = 2,
        ImageCount            = 2,
        MSAASamples           = 0,
        UseDynamicRendering   = true,
        ColorAttachmentFormat = RenderingContext.BACKBUFFER_FORMAT,
        Allocator             = null,
        CheckVkResultFn       = null,
    };
    ImGui_ImplVulkan_Init(*imgui_rendering_init_info, VK_NULL_HANDLE); defer ImGui_ImplVulkan_Shutdown();
    imgui_create_fonts_texture(*rendering_context);

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
ImGui         :: #import "ImGui";

#import "imgui_impl_win32";
#import "imgui_impl_vulkan";

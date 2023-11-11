/*
    Briefing:
        create  :: ()
        destroy :: ()
        update  :: ()
 */

RenderingContext :: struct {
    INFINITE             : u64      : 0xFFFF_FFFF_FFFF_FFFF;
    INVALID_FAMILY_INDEX : u32      : 0xFFFF_FFFF;
    MAX_FRAMES_IN_FLIGHT : u64      : 2;
    BACKBUFFER_FORMAT    : VkFormat : .VK_FORMAT_B8G8R8A8_UNORM;

    jai_context : *Context;
    window      : *Window.Window;

    #if GPU_DEBUG {
        shaders_recompiler : RuntimeShadersRecompiler;
    }

    instance        : VkInstance       = VK_NULL_HANDLE;
    api_version     : u32              = 0;
    physical_device : VkPhysicalDevice = VK_NULL_HANDLE;
    device          : VkDevice         = VK_NULL_HANDLE;
    family_index    : u32              = INVALID_FAMILY_INDEX;
    queue           : VkQueue          = VK_NULL_HANDLE;
    surface         : VkSurfaceKHR     = VK_NULL_HANDLE;
    swapchain       : Swapchain        = .{};

    pipeline              : VkPipeline            = VK_NULL_HANDLE;
    pipeline_layout       : VkPipelineLayout      = VK_NULL_HANDLE;
    descriptor_set_layout : VkDescriptorSetLayout = VK_NULL_HANDLE;
    descriptor_pool       : VkDescriptorPool      = VK_NULL_HANDLE;
    descriptor_sets       : [MAX_FRAMES_IN_FLIGHT]VkDescriptorSet;

    // @Cleanup: merge into some kind of memory buffer?
    // @Todo: merge vertex & index buffers into a single one
    texture_image        : Texture;
    texture_image_memory : VkDeviceMemory = VK_NULL_HANDLE;
    texture_sampler      : VkSampler      = VK_NULL_HANDLE;
    vertex_buffer        : VkBuffer       = VK_NULL_HANDLE;
    vertex_buffer_memory : VkDeviceMemory = VK_NULL_HANDLE;
    index_buffer         : VkBuffer       = VK_NULL_HANDLE;
    index_buffer_memory  : VkDeviceMemory = VK_NULL_HANDLE;

    uniform_buffers        : [MAX_FRAMES_IN_FLIGHT]VkBuffer;
    uniform_buffers_memory : [MAX_FRAMES_IN_FLIGHT]VkDeviceMemory;  // @Todo: might be a one continuous memory blob?
    uniform_buffers_mapped : [MAX_FRAMES_IN_FLIGHT]*void;

    command_pools   : [..]VkCommandPool;
    command_buffers : [..]VkCommandBuffer;

    acquire_semaphore : VkSemaphore = VK_NULL_HANDLE;
    submit_semaphore  : VkSemaphore = VK_NULL_HANDLE;
    fences            : [..]VkFence;
    frame_index       : u64 = 0;

    debug_messenger : VkDebugUtilsMessengerEXT = VK_NULL_HANDLE;

    FILL_WINDOW_RECT :: false;

    // @Cleanup: it's a temporary thing
    #if FILL_WINDOW_RECT {
        verticies :: Vertex.[
            .{.{-1.0, -1.0}, .{1.0, 1.0, 1.0}},
            .{.{ 1.0, -1.0}, .{0.0, 1.0, 0.0}},
            .{.{-1.0,  1.0}, .{0.0, 0.0, 1.0}},
            .{.{ 1.0, -1.0}, .{0.0, 1.0, 0.0}},
            .{.{-1.0,  1.0}, .{0.0, 0.0, 1.0}},
            .{.{ 1.0,  1.0}, .{1.0, 0.0, 1.0}},
        ];
    } else {
        verticies :: Vertex.[
            .{.{-0.5, -0.5}, .{1.0, 0.0, 0.0}, .{0.0, 1.0}},
            .{.{ 0.5, -0.5}, .{0.0, 1.0, 0.0}, .{1.0, 1.0}},
            .{.{ 0.5,  0.5}, .{0.0, 0.0, 1.0}, .{1.0, 0.0}},
            .{.{-0.5,  0.5}, .{1.0, 1.0, 1.0}, .{0.0, 0.0}},
        ];

        indicies :: u16.[
           0, 1, 2, 2, 3, 0
        ];
    }
}

create :: (using this : *RenderingContext, with_window : *Window.Window) {
    jai_context = *context;
    window = with_window;

    create_instance(this);
    #if GPU_DEBUG { setup_debug_messenger(this); }
    select_physical_device(this);
    create_logical_device(this);
    create_surface(this);
    create_swapchain(this);
    create_descriptor_set_layout(this);
    create_graphics_pipeline(this);
    create_command_pools(this);
    create_command_buffers(this);
    create_texture_image(this);
    create_texture_sampler(this);
    create_vertex_buffer(this);
    create_index_buffer(this);
    create_uniform_buffers(this);
    create_descriptor_pool(this);
    create_descriptor_sets(this);
    create_sync_objects(this);
    #if GPU_DEBUG { setup_shaders_recompiler(*shaders_recompiler); }
}

destroy :: (using this : *RenderingContext) {
    vkDeviceWaitIdle(device);

    #if GPU_DEBUG { destroy_shaders_recompiler(*shaders_recompiler); }
    destroy_sync_objects(this);
    destroy_descriptor_pool(this);
    destroy_uniform_buffers(this);
    destroy_index_buffer(this);
    destroy_texture_sampler(this);
    destroy_texture_image(this);
    destroy_vertex_buffer(this);
    destroy_command_buffers(this);
    destroy_command_pools(this);
    destroy_graphics_pipeline(this);
    destroy_descriptor_set_layout(this);
    destroy_swapchain(this, *swapchain);
    destroy_surface(this);
    destroy_logical_device(this);
    #if GPU_DEBUG { destroy_debug_messenger(this); }
    destroy_instance(this);

    this.* = .{};
}

update :: (using this : *RenderingContext) {
    #if GPU_DEBUG {
        if shaders_recompiler.has_changed_shaders {
            Thread.lock(*shaders_recompiler.changed_shaders_lock); defer Thread.unlock(*shaders_recompiler.changed_shaders_lock);

            for *changed_shader : shaders_recompiler.changed_shaders_pool {
                Basic.print("[---] Shader is updated: %\n", changed_shader.path);
            }

            // @FIXME: too hackish, but okay for now
            {
                vkDeviceWaitIdle(device);
                destroy_graphics_pipeline(this);
                create_graphics_pipeline(this);
            }
            consume_changed_shaders_pool(*shaders_recompiler);
        }
    }

    draw_frame(this);
}

#scope_file

#import "stb_image";
#import "Vulkan";

#load "vulkan_loader.jai";

#load "vk_buffer.jai";
#load "vk_command.jai";
#load "vk_debug_utils.jai";
#load "vk_texture.jai";
#load "vk_vertex.jai";
#load "vk_imgui.jai";

#if GPU_DEBUG {
    #load "runtime_shaders_recompiler.jai";
}

Swapchain :: struct {
    handle         : VkSwapchainKHR = VK_NULL_HANDLE;
    buffers        : [..]Texture;
    buffers_format : VkFormat       = .UNDEFINED;
}

// @Cleanup
vkCmdBeginRendering             : PFN_vkCmdBeginRendering;
vkCmdEndRendering               : PFN_vkCmdEndRendering;
vkCreateDebugUtilsMessengerEXT  : PFN_vkCreateDebugUtilsMessengerEXT;
vkDestroyDebugUtilsMessengerEXT : PFN_vkDestroyDebugUtilsMessengerEXT;

create_instance :: (using this : *RenderingContext) {
    INSTANCE_EXTENSIONS :: #run instance_extensions_list(
        required = .[
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
            "VK_EXT_swapchain_colorspace",
        ],
        debug = .[
            "VK_EXT_debug_utils",
        ]
    );
    LAYERS :: #run layers_list(
        required = .[
            // @TODO
        ],
        debug = .[
            "VK_LAYER_KHRONOS_validation",
        ]
    );
    PROJECT_NAME :: #run convert_to_c_style_string(#run BUILD_CONFIG.project_name);

    instance_extensions := create_pointers_array_to(INSTANCE_EXTENSIONS);
    instance_layers     := create_pointers_array_to(LAYERS);

    application_info : VkApplicationInfo = .{
        pApplicationName   = PROJECT_NAME.data,
        applicationVersion = 0xdeadd06,
        pEngineName        = null,
        engineVersion      = 0x1337,
        apiVersion         = VK_API_VERSION_1_3,
    };

    instance_create_info : VkInstanceCreateInfo = .{
        flags                   = 0,
        pApplicationInfo        = *application_info,
        enabledLayerCount       = instance_layers.count,
        ppEnabledLayerNames     = instance_layers.data,
        enabledExtensionCount   = instance_extensions.count,
        ppEnabledExtensionNames = instance_extensions.data,
    };

    vk_call(vkCreateInstance(*instance_create_info, null, *instance));

    // @Cleanup
    vkCmdBeginRendering             = xx vkGetInstanceProcAddr(instance, "vkCmdBeginRendering");
    vkCmdEndRendering               = xx vkGetInstanceProcAddr(instance, "vkCmdEndRendering");
    vkCreateDebugUtilsMessengerEXT  = xx vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    vkDestroyDebugUtilsMessengerEXT = xx vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
}

destroy_instance :: (using this : *RenderingContext) {
    vkDestroyInstance(instance, null);
}

setup_debug_messenger :: (using this : *RenderingContext) {
    debug_messenger_callback :: (
        message_severety : VkDebugUtilsMessageSeverityFlagBitsEXT,
        message_types    : VkDebugUtilsMessageTypeFlagsEXT,
        callback_data    : *VkDebugUtilsMessengerCallbackDataEXT,
        user_data        : *void
    ) -> VkBool32 #c_call {
        using this : *RenderingContext = user_data;

        push_context jai_context {
            // @TODO: strip messages
            Basic.print("VULKAN: %\n\n", to_string(callback_data.pMessage));
        }

        return VK_FALSE;
    }

    messenger_create_info := VkDebugUtilsMessengerCreateInfoEXT.{
        sType           = .VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        pNext           = null,
        flags           = 0,
        messageSeverity = .VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT
                        | .VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
                        | .VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        messageType = .VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT
                    | .VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
                    | .VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT
                    | .VK_DEBUG_UTILS_MESSAGE_TYPE_DEVICE_ADDRESS_BINDING_BIT_EXT,
        pfnUserCallback = debug_messenger_callback,
        pUserData       = this,
    };

    vk_call(vkCreateDebugUtilsMessengerEXT(instance, *messenger_create_info, null, *debug_messenger));
}

destroy_debug_messenger :: (using this : *RenderingContext) {
    vkDestroyDebugUtilsMessengerEXT(instance, debug_messenger, null);
}

select_physical_device :: (using this : *RenderingContext) {
    //
    // Physical device selection
    //
    {
        physical_devices_count : u32 = ---;
        vk_call(vkEnumeratePhysicalDevices(instance, *physical_devices_count, null));
        Basic.assert(physical_devices_count > 0);
        Basic.assert(physical_devices_count == 1); // @TODO: remove me

        physical_devices : [16]VkPhysicalDevice = ---;
        physical_devices_count = Basic.min(physical_devices_count, cast(u32) physical_devices.count);
        vk_call(vkEnumeratePhysicalDevices(instance, *physical_devices_count, physical_devices.data));

        physical_device = physical_devices[0]; // @TODO: revisit
    }

    //
    // Queue families info gathering
    //
    {
        queue_families : []VkQueueFamilyProperties;
        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, cast(*u32) *queue_families.count, null);
        Basic.assert(queue_families.count > 0);

        queue_families.data = Basic.alloc(queue_families.count * size_of(VkQueueFamilyProperties), Basic.temporary_allocator);
        vkGetPhysicalDeviceQueueFamilyProperties(physical_device, cast(*u32) *queue_families.count, queue_families.data);

        for family, ix : queue_families {
            if family.queueFlags & (.VK_QUEUE_GRAPHICS_BIT | .VK_QUEUE_COMPUTE_BIT | .VK_QUEUE_TRANSFER_BIT) {
                family_index = cast(u32)ix;
                break;
            }
        }
        Basic.assert(family_index != INVALID_FAMILY_INDEX);
    }
}

create_logical_device :: (using this : *RenderingContext) {
    PRIORITIES :: float32.[1.];
    queue_create_info := VkDeviceQueueCreateInfo.{
        sType            = .VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        pNext            = null,
        flags            = 0,
        queueFamilyIndex = family_index,
        queueCount       = PRIORITIES.count,
        pQueuePriorities = PRIORITIES.data,
    };

    features_1_3 := VkPhysicalDeviceVulkan13Features.{
        sType            = .VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext            = null,
        dynamicRendering = VK_TRUE,
    };

    features_1_0 := VkPhysicalDeviceFeatures2.{
        sType    = .VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        pNext    = *features_1_3,
        features = .{
            shaderFloat64     = VK_TRUE,
            samplerAnisotropy = VK_TRUE,
        },
    };

    DEVICE_EXTENSIONS :: #run device_extensions_list(
        required = .[
            "VK_KHR_swapchain",
            "VK_KHR_maintenance4",
        ]
    );

    device_extensions := create_pointers_array_to(DEVICE_EXTENSIONS);
    device_create_info := VkDeviceCreateInfo.{
        sType                   = .VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        pNext                   = *features_1_0,
        flags                   = 0,
        queueCreateInfoCount    = 1,
        pQueueCreateInfos       = *queue_create_info,
        enabledLayerCount       = 0,
        ppEnabledLayerNames     = null,
        enabledExtensionCount   = device_extensions.count,
        ppEnabledExtensionNames = device_extensions.data,
        pEnabledFeatures        = null,
    };

    vk_call(vkCreateDevice(physical_device, *device_create_info, null, *device));
    vkGetDeviceQueue(device, family_index, 0, *queue);
}

destroy_logical_device :: (using this : *RenderingContext) {
    vkDestroyDevice(device, null);
    device = VK_NULL_HANDLE;
}

create_descriptor_set_layout :: (using this : *RenderingContext) {
    ubo_layout_binding := VkDescriptorSetLayoutBinding.{
        binding            = 0,
        descriptorType     = .UNIFORM_BUFFER,
        descriptorCount    = 1,
        stageFlags         = .VERTEX_BIT,
        pImmutableSamplers = null,
    };

    sampler_layout_binding := VkDescriptorSetLayoutBinding.{
        binding            = 1,
        descriptorCount    = 1,
        descriptorType     = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        pImmutableSamplers = null,
        stageFlags         = .VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    bindings : [2]VkDescriptorSetLayoutBinding = .[
        ubo_\   layout_binding,
        sampler_layout_binding,
    ];
    layout_info := VkDescriptorSetLayoutCreateInfo.{
        bindingCount = cast(u32) bindings.count,
        pBindings    =           bindings.data,
    };

    vk_call(vkCreateDescriptorSetLayout(device, *layout_info, null, *descriptor_set_layout));
}

destroy_descriptor_set_layout :: (using this : *RenderingContext) {
    vkDestroyDescriptorSetLayout(device, descriptor_set_layout, null);
}

create_graphics_pipeline :: (using this : *RenderingContext) {
    load_shader :: (path : string) -> (shader : VkShaderModule #must) #expand {
        shader_binary, success := File.read_entire_file(path);
        Basic.assert(success);
        Basic.assert(shader_binary.count % size_of(u32) == 0);

        defer Basic.free(shader_binary);

        shader_module_create_info : VkShaderModuleCreateInfo = .{
            sType    = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            pNext    = null,
            flags    = 0,
            codeSize = cast(u32)shader_binary.count,
            pCode    = cast(*u32)shader_binary.data,
        };

        shader_module : VkShaderModule = ---;
        vk_call(vkCreateShaderModule(`device, *shader_module_create_info, null, *shader_module));

        return shader_module;
    }

    // @Cleanup
    executable_path := System.get_path_of_running_executable();
    bin_path        := String.slice(executable_path, 0, String.find_index_from_right(executable_path, #char "/"));

    vertex_shader   := load_shader(Basic.sprint("%/%", bin_path, "shaders/triangle.vert.spv"));
    fragment_shader := load_shader(Basic.sprint("%/%", bin_path, "shaders/mandelbrot.frag.spv"));
    defer {
        vkDestroyShaderModule(device, vertex_shader  , null);
        vkDestroyShaderModule(device, fragment_shader, null);
    }

    //
    // Setup pipeline layout
    //
    {
        range : VkPushConstantRange = .{
            stageFlags = .VK_SHADER_STAGE_FRAGMENT_BIT,
            offset     = 0,
            size       = 8,
        };

        pipeline_layout_create_info : VkPipelineLayoutCreateInfo = .{
            sType                  = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            pNext                  = null,
            flags                  = 0,
            setLayoutCount         = 1,
            pSetLayouts            = *descriptor_set_layout,
            pushConstantRangeCount = 1,
            pPushConstantRanges    = *range,
        };
        vk_call(vkCreatePipelineLayout(device, *pipeline_layout_create_info, null, *pipeline_layout));
    }

    //
    // Create pipeline
    //
    {
        VERTEX_STAGE_INDEX   :: 0;
        FRAGMENT_STAGE_INDEX :: 1;

        stages : [2]VkPipelineShaderStageCreateInfo = ---;
        stages[VERTEX_STAGE_INDEX] = .{
            sType               = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            pNext               = null,
            flags               = 0,
            stage               = .VK_SHADER_STAGE_VERTEX_BIT,
            module              = vertex_shader,
            pName               = "main",
            pSpecializationInfo = null,
        };
        stages[FRAGMENT_STAGE_INDEX] = .{
            sType               = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            pNext               = null,
            flags               = 0,
            stage               = .VK_SHADER_STAGE_FRAGMENT_BIT,
            module              = fragment_shader,
            pName               = "main",
            pSpecializationInfo = null,
        };

        vertex_binding_description     := get_vertex_binding_description();
        vertex_attribute_descriptions  := get_vertex_attribute_descriptions();
        vertex_input_state_create_info := VkPipelineVertexInputStateCreateInfo.{
            sType                           = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            pNext                           = null,
            flags                           = 0,
            vertexBindingDescriptionCount   = 1,
            pVertexBindingDescriptions      = *vertex_binding_description,
            vertexAttributeDescriptionCount = xx vertex_attribute_descriptions.count,
            pVertexAttributeDescriptions    = vertex_attribute_descriptions.data,
        };

        assembly_state_create_info : VkPipelineInputAssemblyStateCreateInfo = .{
            sType                  = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            pNext                  = null,
            flags                  = 0,
            topology               = .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable = VK_FALSE,
        };

        viewport_state_create_info : VkPipelineViewportStateCreateInfo = .{
            sType         = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            pNext         = null,
            flags         = 0,
            viewportCount = 1,
            pViewports    = null,
            scissorCount  = 1,
            pScissors     = null,
        };

        rasterization_state_create_info : VkPipelineRasterizationStateCreateInfo = .{
            sType                   = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            pNext                   = null,
            flags                   = 0,
            depthClampEnable        = VK_FALSE,
            rasterizerDiscardEnable = VK_FALSE, // todo: revisit maybe later
            polygonMode             = .VK_POLYGON_MODE_FILL,
            cullMode                = .VK_CULL_MODE_NONE,
            frontFace               = .VK_FRONT_FACE_CLOCKWISE,
            depthBiasEnable         = VK_FALSE,
            depthBiasConstantFactor = 0.,
            depthBiasClamp          = 0.,
            depthBiasSlopeFactor    = 0.,
            lineWidth               = 1.,
        };

        multisample_state_create_info : VkPipelineMultisampleStateCreateInfo = .{
            sType                 = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            pNext                 = null,
            flags                 = 0,
            rasterizationSamples  = .VK_SAMPLE_COUNT_1_BIT,
            sampleShadingEnable   = VK_FALSE,
            minSampleShading      = 0.,
            pSampleMask           = null,
            alphaToCoverageEnable = VK_FALSE,
            alphaToOneEnable      = VK_FALSE,
        };

        color_blend_attachment_state : VkPipelineColorBlendAttachmentState = .{
            blendEnable         = VK_FALSE,
            srcColorBlendFactor = .VK_BLEND_FACTOR_ZERO,
            dstColorBlendFactor = .VK_BLEND_FACTOR_ZERO,
            colorBlendOp        = .VK_BLEND_OP_ADD,
            srcAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO,
            dstAlphaBlendFactor = .VK_BLEND_FACTOR_ZERO,
            alphaBlendOp        = .VK_BLEND_OP_ADD,
            colorWriteMask      = .VK_COLOR_COMPONENT_R_BIT
                                | .VK_COLOR_COMPONENT_G_BIT
                                | .VK_COLOR_COMPONENT_B_BIT
                                | .VK_COLOR_COMPONENT_A_BIT
        };

        color_blend_state_create_info : VkPipelineColorBlendStateCreateInfo = .{
            sType           = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            pNext           = null,
            flags           = 0,
            logicOpEnable   = VK_FALSE,
            logicOp         = .VK_LOGIC_OP_CLEAR,
            attachmentCount = 1,
            pAttachments    = *color_blend_attachment_state,
            blendConstants  = .[0, 0, 0, 0],
        };

        rendering_create_info : VkPipelineRenderingCreateInfo = .{
            sType                   = .VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            pNext                   = null,
            viewMask                = 0,
            colorAttachmentCount    = 1,
            pColorAttachmentFormats = *swapchain.buffers_format,
            depthAttachmentFormat   = .VK_FORMAT_UNDEFINED,
            stencilAttachmentFormat = .VK_FORMAT_UNDEFINED,
        };

        DYNAMIC_STATES :: VkDynamicState.[
            .VK_DYNAMIC_STATE_VIEWPORT,
            .VK_DYNAMIC_STATE_SCISSOR,
        ];

        dynamic_state_create_info : VkPipelineDynamicStateCreateInfo = .{
            sType             = .VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            pNext             = null,
            flags             = 0,
            dynamicStateCount = DYNAMIC_STATES.count,
            pDynamicStates    = DYNAMIC_STATES.data,
        };
        #if GPU_DEBUG {
            PIPELINE_CREATE_FLAGS : VkPipelineCreateFlags : .VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT;
        } else {
            PIPELINE_CREATE_FLAGS : VkPipelineCreateFlags : 0;
        }

        pipeline_create_info : VkGraphicsPipelineCreateInfo = .{
            sType               = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            pNext               = *rendering_create_info,
            flags               = PIPELINE_CREATE_FLAGS,
            stageCount          = 2,
            pStages             = stages.data,
            pVertexInputState   = *vertex_input_state_create_info,
            pInputAssemblyState = *assembly_state_create_info,
            pTessellationState  = null,
            pViewportState      = *viewport_state_create_info,
            pRasterizationState = *rasterization_state_create_info,
            pMultisampleState   = *multisample_state_create_info,
            pDepthStencilState  = null,
            pColorBlendState    = *color_blend_state_create_info,
            pDynamicState       = *dynamic_state_create_info,
            layout              = pipeline_layout,
            renderPass          = VK_NULL_HANDLE,
            subpass             = 0,
            basePipelineHandle  = VK_NULL_HANDLE,
            basePipelineIndex   = 0,
        };
        vk_call(vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, *pipeline_create_info, null, *pipeline));
    }
}

destroy_graphics_pipeline :: inline (using this : *RenderingContext) {
    vkDestroyPipeline(device, pipeline, null);
    vkDestroyPipelineLayout(device, pipeline_layout, null);

    pipeline        = VK_NULL_HANDLE;
    pipeline_layout = VK_NULL_HANDLE;
}

create_surface :: (using this : *RenderingContext) {
    win32_app_instance  : HINSTANCE = GetModuleHandleW(null);
    surface_create_info : VkWin32SurfaceCreateInfoKHR = .{
        hinstance = win32_app_instance,
        hwnd      = window.handle,
    };
    vk_call(vkCreateWin32SurfaceKHR(instance, *surface_create_info, null, *surface));
}

destroy_surface :: inline (using this : *RenderingContext) {
    vkDestroySurfaceKHR(instance, surface, null);
}

create_swapchain :: inline (using this : *RenderingContext) {
    recreate_swapchain(this);
}

recreate_swapchain :: (using this : *RenderingContext) {
    vk_call(vkDeviceWaitIdle(device));

    old_swapchain : *Swapchain = *swapchain;
    new_swapchain :  Swapchain;

    width  : u32;
    height : u32;

    //
    // Swapchain creation
    //
    {
        //
        //  Queriyng supported image capabilities of swapchain buffer
        //
        capabilities : VkSurfaceCapabilitiesKHR = ---;
        vk_call(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, *capabilities));

        //
        // Querying supported formats
        //
        formats_count : u32 = 0;
        vk_call(vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, *formats_count, null));
        Basic.assert(formats_count > 0);

        formats : [..]VkSurfaceFormatKHR;
        Basic.array_resize(*formats, formats_count);
        defer Basic.array_free(formats);

        vk_call(vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, *formats_count, formats.data));
        Basic.print("[---] %\n", formats);


        //
        // The actual creation of the swapchain
        //
        SWAPCHAIN_BUFFERS_COUNT : u32 : 2;
        Basic.assert(capabilities.minImageCount <= SWAPCHAIN_BUFFERS_COUNT && (capabilities.maxImageCount == 0 || SWAPCHAIN_BUFFERS_COUNT <= capabilities.maxImageCount));

        surface_format    : *VkSurfaceFormatKHR = null;
        for format, ix : formats {
            if (format.format == BACKBUFFER_FORMAT) {
                surface_format = *formats[ix];
                break;
            }
        }
        Basic.assert(surface_format != null);
        new_swapchain.buffers_format = BACKBUFFER_FORMAT;

        queue_families_with_access_to_backbuffers : [1]u32 = .[ family_index ];


        // width  := window.width;
        // height := window.height;
        // Basic.assert(capabilities.minImageExtent.width <= width && width <= capabilities.maxImageExtent.width);
        // Basic.assert(capabilities.minImageExtent.height <= height && height <= capabilities.maxImageExtent.height);

        width  = Basic.clamp(window.width,  capabilities.minImageExtent.width,  capabilities.maxImageExtent.width );
        height = Basic.clamp(window.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

        IMAGE_USAGE : VkImageUsageFlags : .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
                                        | .VK_IMAGE_USAGE_TRANSFER_DST_BIT
                                        | .VK_IMAGE_USAGE_SAMPLED_BIT;
        Basic.assert((capabilities.supportedUsageFlags & IMAGE_USAGE) == IMAGE_USAGE);

        swapchain_create_info : VkSwapchainCreateInfoKHR = .{
            surface               = surface,
            minImageCount         = SWAPCHAIN_BUFFERS_COUNT,
            imageFormat           = surface_format.format,
            imageColorSpace       = surface_format.colorSpace,
            // imageColorSpace       = .VK_COLOR_SPACE_EXTENDED_SRGB_LINEAR_EXT,
            imageExtent           = .{width = width, height = height},
            imageArrayLayers      = 1,
            imageUsage            = IMAGE_USAGE,
            imageSharingMode      = ifx queue_families_with_access_to_backbuffers.count > 1 then .VK_SHARING_MODE_CONCURRENT else .VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount = queue_families_with_access_to_backbuffers.count,
            pQueueFamilyIndices   = queue_families_with_access_to_backbuffers.data,
            preTransform          = capabilities.currentTransform,
            compositeAlpha        = .VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            presentMode           = .VK_PRESENT_MODE_IMMEDIATE_KHR, // VK_PRESENT_MODE_MAILBOX_KHR,
            clipped               = VK_TRUE,
            oldSwapchain          = old_swapchain.handle,
        };
        vk_call(vkCreateSwapchainKHR(device, *swapchain_create_info, null, *new_swapchain.handle));
    }

    //
    // Swapchain buffers extraction
    //
    {
        swapchain_buffers := *new_swapchain.buffers;

        swapchain_buffers_count : u32 = 0;
        vk_call(vkGetSwapchainImagesKHR(device, new_swapchain.handle, *swapchain_buffers_count, null));

        images : [..]VkImage;
        defer Basic.array_free(images);

        Basic.array_resize(*images, swapchain_buffers_count);
        vk_call(vkGetSwapchainImagesKHR(device, new_swapchain.handle, *swapchain_buffers_count, images.data));

        Basic.array_resize(swapchain_buffers, swapchain_buffers_count);
        for image, ix : images {
            buffer : *Texture = *(swapchain_buffers.*)[ix];
            buffer.*          = .{
                width  = width,
                height = height,
                image  = image,
            };

            image_view_create_info : VkImageViewCreateInfo = .{
                image      = buffer.image,
                viewType   = .VK_IMAGE_VIEW_TYPE_2D,
                format     = new_swapchain.buffers_format,
                components = .{
                    r = .VK_COMPONENT_SWIZZLE_R,
                    g = .VK_COMPONENT_SWIZZLE_G,
                    b = .VK_COMPONENT_SWIZZLE_B,
                    a = .VK_COMPONENT_SWIZZLE_A,
                },
                subresourceRange = .{
                    aspectMask     = .VK_IMAGE_ASPECT_COLOR_BIT,
                    baseMipLevel   = 0,
                    levelCount     = 1,
                    baseArrayLayer = 0,
                    layerCount     = 1,
                },
            };
            vk_call(vkCreateImageView(device, *image_view_create_info, null, *buffer.rtv));
        }
    }

    destroy_swapchain(this, old_swapchain);
    swapchain = new_swapchain;
}

destroy_swapchain :: inline (using,only(device) this : *RenderingContext, swapchain : *Swapchain) {
    for buffer : swapchain.buffers {
        vkDestroyImageView(device, buffer.rtv, null);
    }
    vkDestroySwapchainKHR(device, swapchain.handle, null);
    Basic.array_free(swapchain.buffers);
}

create_command_pools :: (using this : *RenderingContext) {
    Basic.array_resize(*command_pools, swapchain.buffers.count);
    command_pool_create_info : VkCommandPoolCreateInfo = .{
        queueFamilyIndex = family_index
    };
    for ix : 0..command_pools.count - 1 {
        vk_call(vkCreateCommandPool(device, *command_pool_create_info, null, *command_pools[ix]));
    }
}

destroy_command_pools :: inline (using this : *RenderingContext) {
    for command_pool : command_pools {
        vkDestroyCommandPool(device, command_pool, null);
    }
    Basic.array_free(command_pools);
}

create_command_buffers :: (using this : *RenderingContext) {
    Basic.array_resize(*command_buffers, swapchain.buffers.count);
    {
        allocate_info : VkCommandBufferAllocateInfo = .{
            level              = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandBufferCount = 1,
        };
        for command_pool, ix : command_pools {
            allocate_info.commandPool = command_pool;
            result := vkAllocateCommandBuffers(device, *allocate_info, *command_buffers[ix]);
            vk_call(result);
        }
    }
}

destroy_command_buffers :: inline (using this : *RenderingContext) {
    Basic.array_free(command_buffers);
}

create_texture_image :: (using this : *RenderingContext) {
    width    : s32 = ---;
    height   : s32 = ---;
    channels : s32 = ---;

    pixels: *stbi_uc = stbi_load("assets/textures/texture.jpg", *width, *height, *channels, xx STBI.rgb_alpha);
    Basic.assert(pixels != null, "cannot load the required image");
    defer stbi_image_free(pixels);

    image_size : VkDeviceSize = xx (width * height * 4);

    staging_buffer        : VkBuffer;
    staging_buffer_memory : VkDeviceMemory;
    defer {
        vkDestroyBuffer(device, staging_buffer, null);
        vkFreeMemory(device, staging_buffer_memory, null);
    };

    create_buffer(
        this,
        size       = image_size,
        usage      = .VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        properties = .VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                   | .VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        *staging_buffer,
        *staging_buffer_memory,
    );
    copy_memory(this, pixels, staging_buffer_memory, image_size);

    create_texture(
        this,
        width      = cast(u32) width,
        height     = cast(u32) height,
        format     = .VK_FORMAT_R8G8B8A8_UNORM,
        tiling     = .VK_IMAGE_TILING_OPTIMAL,
        usage      = .VK_IMAGE_USAGE_TRANSFER_DST_BIT | .VK_IMAGE_USAGE_SAMPLED_BIT,
        properties = .VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        *texture_image,
        *texture_image_memory,
    );

    command_pool   := command_pools[0];
    command_buffer := begin_single_time_commands(device, command_pool);
    {
        copy_buffer_to_texture(command_buffer, staging_buffer, *texture_image, width = cast(u32) width, height = cast(u32) height);
        transition_texture_layout(command_buffer, *texture_image, new_layout = .SHADER_READ_ONLY_OPTIMAL);
    }
    end_single_time_commands(command_buffer, device, command_pool, queue);
}

destroy_texture_image :: (using this : *RenderingContext) {
    destroy_texture(device, *texture_image);
    vkFreeMemory(device, texture_image_memory, null);
}

create_texture_sampler :: (using this : *RenderingContext) {
    properties : VkPhysicalDeviceProperties = ---;
    vkGetPhysicalDeviceProperties(physical_device, *properties);

    sampler_info := VkSamplerCreateInfo.{
        magFilter               = .LINEAR,
        minFilter               = .LINEAR,
        addressModeU            = .REPEAT,
        addressModeV            = .REPEAT,
        addressModeW            = .REPEAT,
        anisotropyEnable        = VK_TRUE,
        maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
        borderColor             = .VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        unnormalizedCoordinates = VK_FALSE,
        compareEnable           = VK_FALSE,
        compareOp               = .VK_COMPARE_OP_ALWAYS,
        mipmapMode              = .LINEAR,
        mipLodBias              = 0.0,
        minLod                  = 0.0,
        maxLod                  = 0.0,
    };
    vk_call(vkCreateSampler(device, *sampler_info, null, *texture_sampler));
}

destroy_texture_sampler :: inline (using this : *RenderingContext) {
    vkDestroySampler(device, texture_sampler, null);
}

create_vertex_buffer :: (using this : *RenderingContext) {
    buffer_size : VkDeviceSize = size_of(Vertex) * verticies.count;

    staging_buffer        : VkBuffer       = ---;
    staging_buffer_memory : VkDeviceMemory = ---;
    create_buffer(
        this,
        size       = buffer_size,
        usage      = .VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        properties = .VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                   | .VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        *staging_buffer,
        *staging_buffer_memory,
    );
    copy_memory(this, verticies.data, staging_buffer_memory, buffer_size);

    create_buffer(
        this,
        size       = buffer_size,
        usage      = .VK_BUFFER_USAGE_TRANSFER_DST_BIT
                   | .VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        properties = .VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        *vertex_buffer,
        *vertex_buffer_memory,
    );
    copy_buffer(this, staging_buffer, vertex_buffer, buffer_size);

    vkDestroyBuffer(device, staging_buffer, null);
    vkFreeMemory(device, staging_buffer_memory, null);
}

destroy_vertex_buffer :: (using this : *RenderingContext) {
    vkDestroyBuffer(device, vertex_buffer, null);
    vkFreeMemory(device, vertex_buffer_memory, null);
}

create_index_buffer :: (using this : *RenderingContext) {
    buffer_size : VkDeviceSize = size_of(type_of(indicies[0])) * indicies.count;

    staging_buffer        : VkBuffer = ---;
    staging_buffer_memory : VkDeviceMemory = ---;
    create_buffer(
        this,
        size       = buffer_size,
        usage      = .TRANSFER_SRC_BIT,
        properties = .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
        *staging_buffer,
        *staging_buffer_memory,
    );
    copy_memory(this, indicies.data, staging_buffer_memory, buffer_size);

    create_buffer(
        this,
        size       = buffer_size,
        usage      = .TRANSFER_DST_BIT | .INDEX_BUFFER_BIT,
        properties = .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
        *index_buffer,
        *index_buffer_memory,
    );
    copy_buffer(this, staging_buffer, index_buffer, buffer_size);

    vkDestroyBuffer(device, staging_buffer, null);
    vkFreeMemory(device, staging_buffer_memory, null);
}

destroy_index_buffer :: (using this : *RenderingContext) {
    vkDestroyBuffer(device, index_buffer, null);
    vkFreeMemory(device, index_buffer_memory, null);
}

create_uniform_buffers :: (using this : *RenderingContext) {
    buffer_size : VkDeviceSize : size_of(UniformBufferObject);

    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        create_buffer(
            this,
            size       = buffer_size,
            usage      = .UNIFORM_BUFFER_BIT,
            properties = .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
            *uniform_buffers[i],
            *uniform_buffers_memory[i],
        );

        vkMapMemory(device, uniform_buffers_memory[i], 0, buffer_size, 0, *uniform_buffers_mapped[i]);
    }
}

destroy_uniform_buffers :: (using this : *RenderingContext) {
    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        vkDestroyBuffer(device, uniform_buffers[i], null);
        vkFreeMemory(device, uniform_buffers_memory[i], null);
    }
}

create_descriptor_pool :: (using this : *RenderingContext) {
    pool_sizes : []VkDescriptorPoolSize = .[
        .{
            type            = .VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount = cast(u32) MAX_FRAMES_IN_FLIGHT,
        }, .{
            type            = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            descriptorCount = cast(u32) MAX_FRAMES_IN_FLIGHT,
        },
    ];

    pool_info := VkDescriptorPoolCreateInfo.{
        poolSizeCount = cast(u32) pool_sizes.count,
        pPoolSizes    =           pool_sizes.data,
        maxSets       = cast(u32) MAX_FRAMES_IN_FLIGHT,
    };
    vk_call(vkCreateDescriptorPool(device, *pool_info, null, *descriptor_pool));
}

destroy_descriptor_pool :: (using this : *RenderingContext) {
    vkDestroyDescriptorPool(device, descriptor_pool, null);
}

create_descriptor_sets :: (using this : *RenderingContext) {
    layouts : [MAX_FRAMES_IN_FLIGHT]VkDescriptorSetLayout = ---;
    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        layouts[i] = descriptor_set_layout;
    }

    alloc_info := VkDescriptorSetAllocateInfo.{
        descriptorPool     = descriptor_pool,
        descriptorSetCount = layouts.count,
        pSetLayouts        = layouts.data,
    };

    vk_call(vkAllocateDescriptorSets(device, *alloc_info, descriptor_sets.data));

    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        buffer_info := VkDescriptorBufferInfo.{
            buffer = uniform_buffers[i],
            offset = 0,
            range  = size_of(UniformBufferObject),
        };

        image_info := VkDescriptorImageInfo.{
            imageLayout = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            imageView   = texture_image.rtv,
            sampler     = texture_sampler,
        };

        descriptor_writes : [2]VkWriteDescriptorSet = .[
            .{
                dstSet           = descriptor_sets[i],
                dstBinding       = 0,
                dstArrayElement  = 0,
                descriptorType   = .UNIFORM_BUFFER,
                descriptorCount  = 1,
                pBufferInfo      = *buffer_info,
                pImageInfo       = null,
                pTexelBufferView = null,
            }, .{
                dstSet           = descriptor_sets[i],
                dstBinding       = 1,
                dstArrayElement  = 0,
                descriptorType   = .COMBINED_IMAGE_SAMPLER,
                descriptorCount  = 1,
                pImageInfo       = *image_info
            },
        ];

        vkUpdateDescriptorSets(device, cast(u32) descriptor_writes.count, descriptor_writes.data, 0, null);
    }
}

create_sync_objects :: (using this : *RenderingContext) {
    semaphore_create_info : VkSemaphoreCreateInfo = .{};
    vk_call(vkCreateSemaphore(device, *semaphore_create_info, null, *acquire_semaphore));
    vk_call(vkCreateSemaphore(device, *semaphore_create_info, null, *submit_semaphore));

    Basic.array_resize(*fences, swapchain.buffers.count);
    for ix : 0..fences.count - 1 {
        fence_create_info : VkFenceCreateInfo = .{
            flags = .VK_FENCE_CREATE_SIGNALED_BIT
        };
        vk_call(vkCreateFence(device, *fence_create_info, null, *fences[ix]));
    }
}

destroy_sync_objects :: inline (using this : *RenderingContext) {
    for fence : fences {
        vkDestroyFence(device, fence, null);
    }
    vkDestroySemaphore(device, acquire_semaphore, null);
    vkDestroySemaphore(device, submit_semaphore, null);

    Basic.array_free(fences);
}

acquire_next_backbuffer_index :: (using this : *RenderingContext, backbuffer_index : *u32) -> (result : VkResult) {
    acquire_info : VkAcquireNextImageInfoKHR = .{
        swapchain  = swapchain.handle,
        timeout    = INFINITE - 1,
        semaphore  = acquire_semaphore,
        fence      = VK_NULL_HANDLE,
        deviceMask = 1,
    };
    return vkAcquireNextImage2KHR(device, *acquire_info, backbuffer_index);
}

prepare_frame :: (using this : *RenderingContext) -> (backbuffer_index : u32) {
    frame_index            = (frame_index + 1) % cast(u64) swapchain.buffers.count;
    backbuffer_index : u32 = 0;

    result := acquire_next_backbuffer_index(this, *backbuffer_index);
    if result == .VK_ERROR_OUT_OF_DATE_KHR {
        Thread.lock(*window.lock); defer Thread.unlock(*window.lock);
        recreate_swapchain(this);
        vk_call(acquire_next_backbuffer_index(this, *backbuffer_index));
    } else {
        vk_call(result);
    }

    return backbuffer_index;
}

draw_frame :: (using this : *RenderingContext) {
    backbuffer_index := prepare_frame(this);

    //
    // Wait for submit fence
    //
    {
        vk_call(vkWaitForFences(device, 1, *fences[frame_index], VK_TRUE, INFINITE));
        vk_call(vkResetFences(device, 1, *fences[frame_index]));
    }

    //
    // Update uniform data
    //
    {
        backbuffer := *(swapchain.buffers[backbuffer_index]);

        time := cast(float) Basic.get_time();
        ubo := UniformBufferObject.{
            // Rotates over PI / 2 each second
            model = Math.Matrix4_Identity /* * Math.rotate(Math.Matrix4_Identity, .{
                xyz = Math.sin(Math.PI / 4 /* * time */) * Math.normalize(Math.Vector3.{x = 1.0, y = 0.0, z = 0.0}),
                w   = Math.cos(Math.PI / 4 /* * time */),
            }) */,

            view = look_at_matrix_lh(
                eye       = .{0.0, 0.0, -2.0},
                target    = .{0.0, 0.0,  0.0},
                up_vector = .{0.0, 1.0,  0.0},
            ),

            proj = perspective_lh(
                fov          = Math.PI / 3.0,
                aspect_ratio = cast(float) backbuffer.width / cast(float) backbuffer.height,
                near         = 0.1,
                far          = 1000.0,
            ),
        };

        memcpy(uniform_buffers_mapped[frame_index], *ubo, size_of(UniformBufferObject));
    }

    //
    // Preparing command buffer for the frame
    //
    command_buffer : VkCommandBuffer = command_buffers[frame_index];
    {
        vk_call(vkResetCommandPool(device, command_pools[frame_index], 0));

        command_buffer_begin_info : VkCommandBufferBeginInfo = .{
            flags            = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            pInheritanceInfo = null,
        };
        vk_call(vkBeginCommandBuffer(command_buffer, *command_buffer_begin_info));
    }

    {
        backbuffer : *Texture = *(swapchain.buffers[backbuffer_index]);

        //
        // Rendering
        //
        {
            transition_texture_layout(command_buffer, backbuffer, .VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);

            //
            // Begin rendering
            //
            {
                attachment_info : VkRenderingAttachmentInfo = .{
                    imageView          = backbuffer.rtv,
                    imageLayout        = backbuffer.layout,
                    resolveMode        = .VK_RESOLVE_MODE_NONE,
                    resolveImageView   = VK_NULL_HANDLE,
                    resolveImageLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
                    loadOp             = .VK_ATTACHMENT_LOAD_OP_CLEAR,
                    storeOp            = .VK_ATTACHMENT_STORE_OP_STORE,
                    clearValue         = .{},
                };

                rendering_info : VkRenderingInfo = .{
                    renderArea = .{
                        .{ 0, 0 },
                        .{ backbuffer.width, backbuffer.height },
                    },
                    layerCount           = 1,
                    viewMask             = 0,
                    colorAttachmentCount = 1,
                    pColorAttachments    = *attachment_info,
                    pDepthAttachment     = null,
                    pStencilAttachment   = null,
                };
                vkCmdBeginRendering(command_buffer, *rendering_info);
            }

            //
            // Draw call
            //
            {
                viewport : VkViewport = .{
                    x        = 0,
                    y        = cast(float) backbuffer.height,
                    width    = cast(float) backbuffer.width,
                    height   = -cast(float) backbuffer.height,
                    minDepth = 0.,
                    maxDepth = 1.,
                };
                scissor_rect : VkRect2D = .{
                    .{0           , 0            },
                    .{backbuffer.width, backbuffer.height}
                };

                vkCmdSetViewport(command_buffer, 0, 1, *viewport);
                vkCmdSetScissor(command_buffer, 0, 1, *scissor_rect);

                vkCmdBindPipeline(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

                offsets := VkDeviceSize.[ 0 ];
                vkCmdBindVertexBuffers(command_buffer, 0, 1, *vertex_buffer, offsets.data);
                vkCmdBindIndexBuffer(command_buffer, index_buffer, 0, .UINT16);

                client_area_scale := cast(float) backbuffer.height / cast(float) backbuffer.width;
                data : [2]float = .[
                    client_area_scale,
                    xx Basic.get_time(),
                ];
                vkCmdPushConstants(command_buffer, pipeline_layout, .VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, data.data);

                vkCmdBindDescriptorSets(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_layout, 0, 1, *descriptor_sets[frame_index], 0, null);
                vkCmdDrawIndexed(command_buffer, xx indicies.count, 1, 0, 0, 0);
            }

            ImGui_ImplVulkan_NewFrame();
            ImGui_ImplWin32_NewFrame();
            ImGui.NewFrame();

            ImGui.ShowDemoWindow();

            ImGui.Render();
            draw_data := ImGui.GetDrawData();
            ImGui_ImplVulkan_RenderDrawData(draw_data, command_buffer);


            //
            // End rendering
            //
            {
                vkCmdEndRendering(command_buffer);
            }
        }

        // Should be the last command in the frame
        transition_texture_layout(command_buffer, backbuffer, .VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
    }

    {
        vk_call(vkEndCommandBuffer(command_buffer));
    }

    //
    // Commands submitting
    //
    {
        wait_mask : VkPipelineStageFlags = .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;

        submit_info : VkSubmitInfo = .{
            waitSemaphoreCount   = 1,
            pWaitSemaphores      = *acquire_semaphore,
            pWaitDstStageMask    = *wait_mask,
            commandBufferCount   = 1,
            pCommandBuffers      = *command_buffer,
            signalSemaphoreCount = 1,
            pSignalSemaphores    = *submit_semaphore,
        };
        vk_call(vkQueueSubmit(queue, 1, *submit_info, fences[frame_index]));
    }




    //
    // Presenting
    //
    {
        present_info : VkPresentInfoKHR = .{
            waitSemaphoreCount = 1,
            pWaitSemaphores    = *submit_semaphore,
            swapchainCount     = 1,
            pSwapchains        = *swapchain.handle,
            pImageIndices      = *backbuffer_index,
            pResults           = null,
        };
        result := vkQueuePresentKHR(queue, *present_info);
        if result == .ERROR_OUT_OF_DATE_KHR {
            return;
        } else {
            vk_call(result);
        }
    }
}

#scope_module
// @Cleanup: move to vk_command.jai
begin_single_time_commands :: (device : VkDevice, command_pool : VkCommandPool) -> VkCommandBuffer {
    alloc_info := VkCommandBufferAllocateInfo.{
        level              = .VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandPool        = command_pool,
        commandBufferCount = 1,
    };

    command_buffer : VkCommandBuffer = ---;
    vkAllocateCommandBuffers(device, *alloc_info, *command_buffer);

    begin_info := VkCommandBufferBeginInfo.{
        flags = .VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    vkBeginCommandBuffer(command_buffer, *begin_info);

    return command_buffer;
}

// @Cleanup: move to vk_command.jai
end_single_time_commands :: (command_buffer: VkCommandBuffer, device : VkDevice, command_pool : VkCommandPool, queue :VkQueue) {
    vkEndCommandBuffer(command_buffer);

    submit_info := VkSubmitInfo.{
        commandBufferCount = 1,
        pCommandBuffers    = *command_buffer,
    };
    vkQueueSubmit(queue, 1, *submit_info, VK_NULL_HANDLE);
    vkQueueWaitIdle(queue);

    vkFreeCommandBuffers(device, command_pool, 1, *command_buffer);
}

#scope_file

if_debug :: ($n : s64) -> s64 {
    #if GPU_DEBUG {
        return n;
    }
    return 0;
}

instance_extensions_list :: strings_list;
layers_list              :: strings_list;
device_extensions_list   :: strings_list;

StringsListResult :: struct($required : []string, $optional : []string, $debug : []string) {
    #if GPU_DEBUG {
        count :: required.count + optional.count + debug.count;
    } else {
        count :: required.count + optional.count;
    }

    strings : [count]string;
}

strings_list :: ($required : []string = .[], $optional : []string = .[], $debug : []string = .[]) -> []string {
    result : StringsListResult(required, optional, debug) = ---;

    #if GPU_DEBUG {
        groups : [3][]string = .[required, optional, debug];
    } else {
        groups : [2][]string = .[required, optional];
    }

    ix := 0;
    for group : groups {
        for s : group {
            result.strings[ix] = convert_to_c_style_string(s);
            ix += 1;
        }
    }

    return result.strings;
}

create_pointers_array_to :: (strings : [$count]string) -> [count]*u8 {
    result : [count]*u8 = ---;

    for s, ix : strings {
        result[ix] = s.data;
    }

    return result;
}

#import "Windows";

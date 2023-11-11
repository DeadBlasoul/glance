// dear imgui: Renderer Backend for Vulkan
// This needs to be used along with a Platform Backend (e.g. GLFW, SDL, Win32, custom..)

// Implemented features:
//  [!] Renderer: User texture binding. Use 'VkDescriptorSet' as ImTextureID. Read the FAQ about ImTextureID! See https://github.com/ocornut/imgui/pull/914 for discussions.
//  [X] Renderer: Large meshes support (64k+ vertices) with 16-bit indices.

// Important: on 32-bit systems, user texture binding is only supported if your imconfig file has '#define ImTextureID ImU64'.
// See imgui_impl_vulkan.cpp file for details.

// The aim of imgui_impl_vulkan.h/.cpp is to be usable in your engine without any modification.
// IF YOU FEEL YOU NEED TO MAKE ANY CHANGE TO THIS CODE, please share them and your feedback at https://github.com/ocornut/imgui/

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_vulkan.cpp/.h in their own engine/app.
// - Common ImGui_ImplVulkan_XXX functions and structures are used to interface with imgui_impl_vulkan.cpp/.h.
//   You will use those if you want to use this rendering backend in your engine/app.
// - Helper ImGui_ImplVulkanH_XXX functions and structures are only used by this example (main.cpp) and by
//   the backend itself (imgui_impl_vulkan.cpp), but should PROBABLY NOT be used by your own engine/app code.
// Read comments in imgui_impl_vulkan.h.

#scope_module

ImGui :: #import "ImGui";
         #import "Vulkan";

ImU64          :: ImGui.ImU64;
ImVec2         :: ImGui.ImVec2;
ImDrawVert     :: ImGui.ImDrawVert;
ImDrawIdx      :: ImGui.ImDrawIdx;
ImDrawList     :: ImGui.ImDrawList;
ImDrawData     :: ImGui.ImDrawData;
ImDrawCmd      :: ImGui.ImDrawCmd;
ImDrawCallback :: ImGui.ImDrawCallback;
ImTextureID    :: ImGui.ImTextureID;

ImDrawCallback_ResetRenderState : ImDrawCallback : xx -1;

// [Configuration] in order to use a custom Vulkan function loader:
// (1) You'll need to disable default Vulkan function prototypes.
//     We provide a '#define IMGUI_IMPL_VULKAN_NO_PROTOTYPES' convenience configuration flag.
//     In order to make sure this is visible from the imgui_impl_vulkan.cpp compilation unit:
//     - Add '#define IMGUI_IMPL_VULKAN_NO_PROTOTYPES' in your imconfig.h file
//     - Or as a compilation flag in your build system
//     - Or uncomment here (not recommended because you'd be modifying imgui sources!)
//     - Do not simply add it in a .cpp file!
// (2) Call ImGui_ImplVulkan_LoadFunctions() before ImGui_ImplVulkan_Init() with your custom function.
// If you have no idea what this is, leave it alone!
//#define IMGUI_IMPL_VULKAN_NO_PROTOTYPES

// @Cleanup: implement it in a proper JAI way
// ---
// Vulkan includes
// #if defined(IMGUI_IMPL_VULKAN_NO_PROTOTYPES) && !defined(VK_NO_PROTOTYPES)
// #define VK_NO_PROTOTYPES
// #endif
// #include <vulkan/vulkan.h>

#scope_export

// Initialization data, for ImGui_ImplVulkan_Init()
// [Please zero-clear before use!]
ImGui_ImplVulkan_InitInfo :: struct {
    Instance       : VkInstance;
    PhysicalDevice : VkPhysicalDevice;
    Device         : VkDevice;
    QueueFamily    : u32;
    Queue          : VkQueue;
    PipelineCache  : VkPipelineCache;
    DescriptorPool : VkDescriptorPool;
    Subpass        : u32;
    MinImageCount  : u32;                              // >= 2
    ImageCount     : u32;                              // >= MinImageCount
    MSAASamples    : VkSampleCountFlagBits;            // >= VK_SAMPLE_COUNT_1_BIT (0 -> default to VK_SAMPLE_COUNT_1_BIT)

    // Dynamic Rendering (Optional)
    UseDynamicRendering   : bool;      // Need to explicitly enable VK_KHR_dynamic_rendering extension to use this, even for Vulkan 1.3.
    ColorAttachmentFormat : VkFormat;  // Required for dynamic rendering

    // Allocation, Debugging
    Allocator       : *VkAllocationCallbacks;
    CheckVkResultFn : (err: VkResult) -> void #c_call;
};

/**
// Called by user code
ImGui_ImplVulkan_Init :: (info: *ImGui_ImplVulkan_InitInfo, render_pass: VkRenderPass) -> bool #no_context;
ImGui_ImplVulkan_Shutdown :: () -> void #no_context;
ImGui_ImplVulkan_NewFrame :: () -> void #no_context;
ImGui_ImplVulkan_RenderDrawData :: (ImDrawData* draw_data, VkCommandBuffer command_buffer, VkPipeline pipeline = VK_NULL_HANDLE) -> void #no_context;
ImGui_ImplVulkan_CreateFontsTexture :: (VkCommandBuffer command_buffer) -> bool #no_context;
ImGui_ImplVulkan_DestroyFontUploadObjects :: () -> void #no_context;
ImGui_ImplVulkan_SetMinImageCount :: (uint32_t min_image_count) -> void #no_context; // To override MinImageCount after initialization (e.g. if swap chain is recreated)

// Register a texture (VkDescriptorSet == ImTextureID)
// FIXME: This is experimental in the sense that we are unsure how to best design/tackle this problem
// Please post to https://github.com/ocornut/imgui/pull/914 if you have suggestions.
ImGui_ImplVulkan_AddTexture :: (VkSampler sampler, VkImageView image_view, VkImageLayout image_layout) -> VkDescriptorSet #no_context;
ImGui_ImplVulkan_RemoveTexture :: (VkDescriptorSet descriptor_set) -> void #no_context;
*/

ImGui_ImplVulkan_Init :: (info: *ImGui_ImplVulkan_InitInfo, render_pass: VkRenderPass) -> bool #no_context {
    // IM_ASSERT(g_FunctionsLoaded && "Need to call ImGui_ImplVulkan_LoadFunctions() if IMGUI_IMPL_VULKAN_NO_PROTOTYPES or VK_NO_PROTOTYPES are set!");

    if info.UseDynamicRendering {
//#ifdef IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING
        #if true {
//#ifndef VK_NO_PROTOTYPES
            #if true {
                ImGuiImplVulkanFuncs_vkCmdBeginRenderingKHR = xx vkGetInstanceProcAddr(info.Instance, "vkCmdBeginRenderingKHR");
                ImGuiImplVulkanFuncs_vkCmdEndRenderingKHR = xx vkGetInstanceProcAddr(info.Instance, "vkCmdEndRenderingKHR");
            }
//#endif
            IM_ASSERT(ImGuiImplVulkanFuncs_vkCmdBeginRenderingKHR != null);
            IM_ASSERT(ImGuiImplVulkanFuncs_vkCmdEndRenderingKHR != null);
//#else
        } else {
            IM_ASSERT(0 && "Can't use dynamic rendering when neither VK_VERSION_1_3 or VK_KHR_dynamic_rendering is defined.");
//#endif
        }
    }

    io := ImGui.GetIO();
    IM_ASSERT(io.BackendRendererUserData == null && "Already initialized a renderer backend!");

    // Setup backend capabilities flags
    bd := IM_NEW(ImGui_ImplVulkan_Data);
    io.BackendRendererUserData = cast(*void)bd;
    io.BackendRendererName = "imgui_impl_vulkan";
    io.BackendFlags_ |= .RendererHasVtxOffset;  // We can honor the ImDrawCmd::VtxOffset field, allowing for large meshes.

    IM_ASSERT(info.Instance != VK_NULL_HANDLE);
    IM_ASSERT(info.PhysicalDevice != VK_NULL_HANDLE);
    IM_ASSERT(info.Device != VK_NULL_HANDLE);
    IM_ASSERT(info.Queue != VK_NULL_HANDLE);
    IM_ASSERT(info.DescriptorPool != VK_NULL_HANDLE);
    IM_ASSERT(info.MinImageCount >= 2);
    IM_ASSERT(info.ImageCount >= info.MinImageCount);
    if info.UseDynamicRendering == false {
        IM_ASSERT(render_pass != VK_NULL_HANDLE);
    }

    bd.VulkanInitInfo = info.*;
    bd.RenderPass = render_pass;
    bd.Subpass = info.Subpass;

    ImGui_ImplVulkan_CreateDeviceObjects();

    return true;
}

ImGui_ImplVulkan_Shutdown :: () #no_context {
    bd : *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();
    IM_ASSERT(bd != null && "No renderer backend to shutdown, or already shutdown?");
    io := ImGui.GetIO();

    ImGui_ImplVulkan_DestroyDeviceObjects();
    io.BackendRendererName = null;
    io.BackendRendererUserData = null;
    io.BackendFlags_ &= ~ImGui.BackendFlags.RendererHasVtxOffset;
    IM_DELETE(bd);
}

ImGui_ImplVulkan_NewFrame :: () #no_context {
    bd : *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();
    IM_ASSERT(bd != null && "Did you call ImGui_ImplVulkan_Init()?");
    IM_UNUSED(bd);
}

ImGui_ImplVulkan_SetMinImageCount :: (min_image_count: u32) #no_context {
    bd : *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();
    IM_ASSERT(min_image_count >= 2);
    if (bd.VulkanInitInfo.MinImageCount == min_image_count)
        return;

    v : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    err := vkDeviceWaitIdle(v.Device);
    check_vk_result(err);
    ImGui_ImplVulkanH_DestroyWindowRenderBuffers(v.Device, *bd.MainWindowRenderBuffers, v.Allocator);
    bd.VulkanInitInfo.MinImageCount = min_image_count;
}

// Register a texture
// FIXME: This is experimental in the sense that we are unsure how to best design/tackle this problem, please post to https://github.com/ocornut/imgui/pull/914 if you have suggestions.
ImGui_ImplVulkan_AddTexture :: (sampler: VkSampler, image_view: VkImageView, image_layout: VkImageLayout) -> VkDescriptorSet #no_context {
    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;

    // Create Descriptor Set:
    descriptor_set: VkDescriptorSet = ---;
    {
        alloc_info := VkDescriptorSetAllocateInfo.{
            descriptorPool     = v.DescriptorPool,
            descriptorSetCount = 1,
            pSetLayouts        = *bd.DescriptorSetLayout,
        };
        err := vkAllocateDescriptorSets(v.Device, *alloc_info, *descriptor_set);
        check_vk_result(err);
    }

    // Update the Descriptor Set:
    {
        desc_image : [1]VkDescriptorImageInfo = .[
            VkDescriptorImageInfo.{
                sampler     = sampler,
                imageView   = image_view,
                imageLayout = image_layout,
            },
        ];
        write_desc := VkWriteDescriptorSet.[
            .{
                dstSet          = descriptor_set,
                descriptorCount = desc_image.count,
                descriptorType  = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                pImageInfo      = desc_image.data,
            },
        ];
        vkUpdateDescriptorSets(v.Device, xx write_desc.count, write_desc.data, 0, null);
    }

    return descriptor_set;
}

ImGui_ImplVulkan_RemoveTexture :: (descriptor_set: VkDescriptorSet) -> void #no_context {
    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    vkFreeDescriptorSets(v.Device, v.DescriptorPool, 1, *descriptor_set);
}

ImGui_ImplVulkan_RenderDrawData :: (
    draw_data      : *ImGui.ImDrawData,
    command_buffer : VkCommandBuffer,
    pipeline       : VkPipeline = VK_NULL_HANDLE
) #no_context {
    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    fb_width  : s32 = cast(s32) (draw_data.DisplaySize.x * draw_data.FramebufferScale.x);
    fb_height : s32 = cast(s32) (draw_data.DisplaySize.y * draw_data.FramebufferScale.y);
    if fb_width <= 0 || fb_height <= 0 {
        return;
    }

    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    if pipeline == VK_NULL_HANDLE {
        pipeline = bd.Pipeline;
    }

    // Allocate array to store enough vertex/index buffers
    wrb : *ImGui_ImplVulkanH_WindowRenderBuffers = *bd.MainWindowRenderBuffers;
    if wrb.FrameRenderBuffers == null {
        frame_buffers_size := size_of(ImGui_ImplVulkanH_FrameRenderBuffers) * wrb.Count;
        wrb.Index              = 0;
        wrb.Count              = v.ImageCount;
        wrb.FrameRenderBuffers = ImGui.MemAlloc(size_of(ImGui_ImplVulkanH_FrameRenderBuffers) * wrb.Count);
        memset(wrb.FrameRenderBuffers, 0, frame_buffers_size);
    }
    IM_ASSERT(wrb.Count == v.ImageCount);
    wrb.Index = (wrb.Index + 1) % wrb.Count;
    rb : *ImGui_ImplVulkanH_FrameRenderBuffers = *wrb.FrameRenderBuffers[wrb.Index];

    if draw_data.TotalVtxCount > 0 {
        // Create or resize the vertex/index buffers
        vertex_size : u64 = (cast(u64) draw_data.TotalVtxCount) * size_of(ImDrawVert);
        index_size  : u64 = (cast(u64) draw_data.TotalIdxCount) * size_of(ImDrawIdx);
        if rb.VertexBuffer == VK_NULL_HANDLE || rb.VertexBufferSize < vertex_size {
            rb.VertexBuffer, rb.VertexBufferMemory, rb.VertexBufferSize = CreateOrResizeBuffer(
                rb.VertexBuffer,
                rb.VertexBufferMemory,
                rb.VertexBufferSize,
                vertex_size,
                .VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            );
        }
        if rb.IndexBuffer == VK_NULL_HANDLE || rb.IndexBufferSize < index_size {
            rb.IndexBuffer, rb.IndexBufferMemory, rb.IndexBufferSize = CreateOrResizeBuffer(
                rb.IndexBuffer,
                rb.IndexBufferMemory,
                rb.IndexBufferSize,
                index_size,
                .VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            );
        }

        // Upload vertex/index data into a single contiguous GPU buffer
        vtx_dst : *ImDrawVert = null;
        idx_dst : *ImDrawIdx  = null;
        err := vkMapMemory(v.Device, rb.VertexBufferMemory, 0, rb.VertexBufferSize, 0, cast(**void) *vtx_dst);
        check_vk_result(err);
        err = vkMapMemory(v.Device, rb.IndexBufferMemory, 0, rb.IndexBufferSize, 0, cast(**void) *idx_dst);
        check_vk_result(err);
        for n : 0..draw_data.CmdListsCount - 1 {
            cmd_list : *ImDrawList = draw_data.CmdLists.Data[n];
            memcpy(vtx_dst, cmd_list.VtxBuffer.Data, cmd_list.VtxBuffer.Size * size_of(ImDrawVert));
            memcpy(idx_dst, cmd_list.IdxBuffer.Data, cmd_list.IdxBuffer.Size * size_of(ImDrawIdx));
            vtx_dst += cmd_list.VtxBuffer.Size;
            idx_dst += cmd_list.IdxBuffer.Size;
        }
        range : [2]VkMappedMemoryRange = .[
            VkMappedMemoryRange.{
                memory = rb.VertexBufferMemory,
                size   = VK_WHOLE_SIZE,
            },
            VkMappedMemoryRange.{
                memory = rb.IndexBufferMemory,
                size   = VK_WHOLE_SIZE,
            },
        ];
        err = vkFlushMappedMemoryRanges(v.Device, xx range.count, range.data);
        check_vk_result(err);
        vkUnmapMemory(v.Device, rb.VertexBufferMemory);
        vkUnmapMemory(v.Device, rb.IndexBufferMemory);
    }

    // Setup desired Vulkan state
    ImGui_ImplVulkan_SetupRenderState(draw_data, pipeline, command_buffer, rb, fb_width, fb_height);

    // Will project scissor/clipping rectangles into framebuffer space
    clip_off   : ImVec2 = draw_data.DisplayPos;       // (0,0) unless using multi-viewports
    clip_scale : ImVec2 = draw_data.FramebufferScale; // (1,1) unless using retina display which are often (2,2)

    // Render command lists
    // (Because we merged all buffers into a single one, we maintain our own offset into them)
    global_vtx_offset : s32 = 0;
    global_idx_offset : s32 = 0;
    for n : 0..draw_data.CmdListsCount - 1 {
        cmd_list : *ImDrawList = draw_data.CmdLists.Data[n];
        for cmd_i : 0..cmd_list.CmdBuffer.Size - 1 {
            pcmd : *ImDrawCmd = *cmd_list.CmdBuffer.Data[cmd_i];
            if pcmd.UserCallback != null {
                // User callback, registered via ImDrawList::AddCallback()
                // (ImDrawCallback_ResetRenderState is a special callback value used by the user to request the renderer to reset render state.)
                if pcmd.UserCallback == ImDrawCallback_ResetRenderState {
                    ImGui_ImplVulkan_SetupRenderState(draw_data, pipeline, command_buffer, rb, fb_width, fb_height);
                } else {
                    pcmd.UserCallback(cmd_list, pcmd);
                }
            } else {
                // Project scissor/clipping rectangles into framebuffer space
                clip_min := ImVec2.{(pcmd.ClipRect.x - clip_off.x) * clip_scale.x, (pcmd.ClipRect.y - clip_off.y) * clip_scale.y};
                clip_max := ImVec2.{(pcmd.ClipRect.z - clip_off.x) * clip_scale.x, (pcmd.ClipRect.w - clip_off.y) * clip_scale.y};

                // Clamp to viewport as vkCmdSetScissor() won't accept values that are off bounds
                if clip_min.x < 0.0 { clip_min.x = 0.0; }
                if clip_min.y < 0.0 { clip_min.y = 0.0; }
                if clip_max.x > xx fb_width  { clip_max.x = cast(float) fb_width; }
                if clip_max.y > xx fb_height { clip_max.y = cast(float) fb_height; }
                if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y {
                    continue;
                }

                // Apply scissor/clipping rectangle
                scissor : VkRect2D;
                scissor.offset.x      = cast(s32) clip_min.x;
                scissor.offset.y      = cast(s32) clip_min.y;
                scissor.extent.width  = cast(u32) (clip_max.x - clip_min.x);
                scissor.extent.height = cast(u32) (clip_max.y - clip_min.y);
                vkCmdSetScissor(command_buffer, 0, 1, *scissor);

                // Bind DescriptorSet with font or user texture
                desc_set : [1]VkDescriptorSet = .[ cast(VkDescriptorSet) pcmd.TextureId ];
                #if size_of(ImTextureID) < size_of(ImU64) {
                    // We don't support texture switches if ImTextureID hasn't been redefined to be 64-bit. Do a flaky check that other textures haven't been used.
                    IM_ASSERT(pcmd.TextureId == cast(ImTextureID) bd.FontDescriptorSet);
                    desc_set[0] = bd.FontDescriptorSet;
                }
                vkCmdBindDescriptorSets(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, bd.PipelineLayout, 0, desc_set.count, desc_set.data, 0, null);

                // Draw
                vkCmdDrawIndexed(command_buffer, pcmd.ElemCount, 1, pcmd.IdxOffset + xx global_idx_offset, cast(s32) (pcmd.VtxOffset +  xx global_vtx_offset), 0);
            }
        }
        global_idx_offset += cmd_list.IdxBuffer.Size;
        global_vtx_offset += cmd_list.VtxBuffer.Size;
    }

    // Note: at this point both vkCmdSetViewport() and vkCmdSetScissor() have been called.
    // Our last values will leak into user/application rendering IF:
    // - Your app uses a pipeline with VK_DYNAMIC_STATE_VIEWPORT or VK_DYNAMIC_STATE_SCISSOR dynamic state
    // - And you forgot to call vkCmdSetViewport() and vkCmdSetScissor() yourself to explicitly set that state.
    // If you use VK_DYNAMIC_STATE_VIEWPORT or VK_DYNAMIC_STATE_SCISSOR you are responsible for setting the values before rendering.
    // In theory we should aim to backup/restore those values but I am not sure this is possible.
    // We perform a call to vkCmdSetScissor() to set back a full viewport which is likely to fix things for 99% users but technically this is not perfect. (See github #4644)
    scissor := VkRect2D.{ .{ 0, 0 }, .{ cast(u32) fb_width, cast(u32) fb_height } };
    vkCmdSetScissor(command_buffer, 0, 1, *scissor);
}

ImGui_ImplVulkan_CreateFontsTexture :: (command_buffer : VkCommandBuffer) -> bool {
    io := ImGui.GetIO();
    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;

    pixels : *u8 = ---;
    width  : s32 = ---;
    height : s32 = ---;
    io.Fonts.GetTexDataAsRGBA32(io.Fonts, *pixels, *width, *height);
    upload_size : u64 = cast(u64) (width * height * 4 * size_of(u8));

    err : VkResult = ---;

    // Create the Image:
    {
        info := VkImageCreateInfo.{
            imageType = .VK_IMAGE_TYPE_2D,
            format    = .VK_FORMAT_R8G8B8A8_UNORM,
            extent    = .{
                width  = xx width,
                height = xx height,
                depth  = 1,
            },
            mipLevels     = 1,
            arrayLayers   = 1,
            samples       = .VK_SAMPLE_COUNT_1_BIT,
            tiling        = .VK_IMAGE_TILING_OPTIMAL,
            usage         = .VK_IMAGE_USAGE_SAMPLED_BIT | .VK_IMAGE_USAGE_TRANSFER_DST_BIT,
            sharingMode   = .VK_SHARING_MODE_EXCLUSIVE,
            initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
        };
        err = vkCreateImage(v.Device, *info, v.Allocator, *bd.FontImage);
        check_vk_result(err);
        req : VkMemoryRequirements = ---;
        vkGetImageMemoryRequirements(v.Device, bd.FontImage, *req);
        alloc_info := VkMemoryAllocateInfo.{
            allocationSize  = req.size,
            memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, req.memoryTypeBits),
        };
        err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, *bd.FontMemory);
        check_vk_result(err);
        err = vkBindImageMemory(v.Device, bd.FontImage, bd.FontMemory, 0);
        check_vk_result(err);
    }

    // Create the Image View:
    {
        info := VkImageViewCreateInfo.{
            image            = bd.FontImage,
            viewType         = .VK_IMAGE_VIEW_TYPE_2D,
            format           = .VK_FORMAT_R8G8B8A8_UNORM,
            subresourceRange = .{
                aspectMask = .VK_IMAGE_ASPECT_COLOR_BIT,
                levelCount = 1,
                layerCount = 1,
            },
        };
        err = vkCreateImageView(v.Device, *info, v.Allocator, *bd.FontView);
        check_vk_result(err);
    }

    // Create the Descriptor Set:
    bd.FontDescriptorSet = cast(VkDescriptorSet) ImGui_ImplVulkan_AddTexture(bd.FontSampler, bd.FontView, .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    // Create the Upload Buffer:
    {
        buffer_info : VkBufferCreateInfo = .{
            sType       = .VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            size        = upload_size,
            usage       = .VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
        };
        err = vkCreateBuffer(v.Device, *buffer_info, v.Allocator, *bd.UploadBuffer);
        check_vk_result(err);
        req : VkMemoryRequirements = ---;
        vkGetBufferMemoryRequirements(v.Device, bd.UploadBuffer, *req);
        bd.BufferMemoryAlignment = ifx bd.BufferMemoryAlignment > req.alignment then bd.BufferMemoryAlignment else req.alignment;
        alloc_info := VkMemoryAllocateInfo.{
            allocationSize  = req.size,
            memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, req.memoryTypeBits),
        };
        err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, *bd.UploadBufferMemory);
        check_vk_result(err);
        err = vkBindBufferMemory(v.Device, bd.UploadBuffer, bd.UploadBufferMemory, 0);
        check_vk_result(err);
    }

    // Upload to Buffer:
    {
        map : *s8 = null;
        err = vkMapMemory(v.Device, bd.UploadBufferMemory, 0, upload_size, 0, cast(**void) *map);
        check_vk_result(err);
        memcpy(map, pixels, cast(s64) upload_size);
        range := VkMappedMemoryRange.[
            .{
                memory = bd.UploadBufferMemory,
                size   = upload_size,
            },
        ];
        err = vkFlushMappedMemoryRanges(v.Device, xx range.count, range.data);
        check_vk_result(err);
        vkUnmapMemory(v.Device, bd.UploadBufferMemory);
    }

    // Copy to Image:
    {
        copy_barrier := VkImageMemoryBarrier.[
            .{
                sType               = .VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                dstAccessMask       = .VK_ACCESS_TRANSFER_WRITE_BIT,
                oldLayout           = .VK_IMAGE_LAYOUT_UNDEFINED,
                newLayout           = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                image               = bd.FontImage,
                subresourceRange    = .{
                    aspectMask = .VK_IMAGE_ASPECT_COLOR_BIT,
                    levelCount = 1,
                    layerCount = 1,
                },
            },
        ];
        vkCmdPipelineBarrier(command_buffer, .VK_PIPELINE_STAGE_HOST_BIT, .VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, xx copy_barrier.count, copy_barrier.data);

        region := VkBufferImageCopy.{
            imageSubresource =.{
                aspectMask  = .VK_IMAGE_ASPECT_COLOR_BIT,
                layerCount  = 1,
            },
            imageExtent = .{
                width  = xx width,
                height = xx height,
                depth  = 1,
            },
        };
        vkCmdCopyBufferToImage(command_buffer, bd.UploadBuffer, bd.FontImage, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, *region);

        use_barrier := VkImageMemoryBarrier.[
            VkImageMemoryBarrier.{
                srcAccessMask       = .VK_ACCESS_TRANSFER_WRITE_BIT,
                dstAccessMask       = .VK_ACCESS_SHADER_READ_BIT,
                oldLayout           = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                newLayout           = .VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
                image               = bd.FontImage,
                subresourceRange    = .{
                    aspectMask = .VK_IMAGE_ASPECT_COLOR_BIT,
                    levelCount = 1,
                    layerCount = 1,
                },
            },
        ];
        vkCmdPipelineBarrier(command_buffer, .VK_PIPELINE_STAGE_TRANSFER_BIT, .VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, xx use_barrier.count, use_barrier.data);
    }

    // Store our identifier
    io.Fonts.TexID = cast(ImTextureID) bd.FontDescriptorSet;

    return true;
}

ImGui_ImplVulkan_DestroyFontUploadObjects :: () #no_context {
    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    if bd.UploadBuffer {
        vkDestroyBuffer(v.Device, bd.UploadBuffer, v.Allocator);
        bd.UploadBuffer = VK_NULL_HANDLE;
    }
    if bd.UploadBufferMemory {
        vkFreeMemory(v.Device, bd.UploadBufferMemory, v.Allocator);
        bd.UploadBufferMemory = VK_NULL_HANDLE;
    }
}

#scope_module

// Reusable buffers used for rendering 1 current in-flight frame, for ImGui_ImplVulkan_RenderDrawData()
// [Please zero-clear before use!]
ImGui_ImplVulkanH_FrameRenderBuffers :: struct {
    VertexBufferMemory : VkDeviceMemory;
    IndexBufferMemory  : VkDeviceMemory;
    VertexBufferSize   : VkDeviceSize;
    IndexBufferSize    : VkDeviceSize;
    VertexBuffer       : VkBuffer;
    IndexBuffer        : VkBuffer;
};

// Each viewport will hold 1 ImGui_ImplVulkanH_WindowRenderBuffers
// [Please zero-clear before use!]
ImGui_ImplVulkanH_WindowRenderBuffers :: struct {
    Index              : u32;
    Count              : u32;
    FrameRenderBuffers : *ImGui_ImplVulkanH_FrameRenderBuffers;
};

// Vulkan data
ImGui_ImplVulkan_Data :: struct {
    VulkanInitInfo          : ImGui_ImplVulkan_InitInfo;
    RenderPass              : VkRenderPass;
    BufferMemoryAlignment   : VkDeviceSize = 256;
    PipelineCreateFlags     : VkPipelineCreateFlags;
    DescriptorSetLayout     : VkDescriptorSetLayout;
    PipelineLayout          : VkPipelineLayout;
    Pipeline                : VkPipeline;
    Subpass                 : u32;
    ShaderModuleVert        : VkShaderModule;
    ShaderModuleFrag        : VkShaderModule;

    // Font data
    FontSampler             : VkSampler;
    FontMemory              : VkDeviceMemory;
    FontImage               : VkImage;
    FontView                : VkImageView;
    FontDescriptorSet       : VkDescriptorSet;
    UploadBufferMemory      : VkDeviceMemory;
    UploadBuffer            : VkBuffer;

    // Render buffers for main window
    MainWindowRenderBuffers : ImGui_ImplVulkanH_WindowRenderBuffers;
};

ImGuiImplVulkanFuncs_vkCmdBeginRenderingKHR : PFN_vkCmdBeginRenderingKHR;
ImGuiImplVulkanFuncs_vkCmdEndRenderingKHR   : PFN_vkCmdEndRenderingKHR;

//-----------------------------------------------------------------------------
// SHADERS
//-----------------------------------------------------------------------------

// glsl_shader.vert, compiled with:
// # glslangValidator -V -x -o glsl_shader.vert.u32 glsl_shader.vert
/*
#version 450 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUV;
layout(location = 2) in vec4 aColor;
layout(push_constant) uniform uPushConstant { vec2 uScale; vec2 uTranslate; } pc;

out gl_PerVertex { vec4 gl_Position; };
layout(location = 0) out struct { vec4 Color; vec2 UV; } Out;

void main()
{
    Out.Color = aColor;
    Out.UV = aUV;
    gl_Position = vec4(aPos * pc.uScale + pc.uTranslate, 0, 1);
}
*/
__glsl_shader_vert_spv := u32.[
    0x07230203,0x00010000,0x00080001,0x0000002e,0x00000000,0x00020011,0x00000001,0x0006000b,
    0x00000001,0x4c534c47,0x6474732e,0x3035342e,0x00000000,0x0003000e,0x00000000,0x00000001,
    0x000a000f,0x00000000,0x00000004,0x6e69616d,0x00000000,0x0000000b,0x0000000f,0x00000015,
    0x0000001b,0x0000001c,0x00030003,0x00000002,0x000001c2,0x00040005,0x00000004,0x6e69616d,
    0x00000000,0x00030005,0x00000009,0x00000000,0x00050006,0x00000009,0x00000000,0x6f6c6f43,
    0x00000072,0x00040006,0x00000009,0x00000001,0x00005655,0x00030005,0x0000000b,0x0074754f,
    0x00040005,0x0000000f,0x6c6f4361,0x0000726f,0x00030005,0x00000015,0x00565561,0x00060005,
    0x00000019,0x505f6c67,0x65567265,0x78657472,0x00000000,0x00060006,0x00000019,0x00000000,
    0x505f6c67,0x7469736f,0x006e6f69,0x00030005,0x0000001b,0x00000000,0x00040005,0x0000001c,
    0x736f5061,0x00000000,0x00060005,0x0000001e,0x73755075,0x6e6f4368,0x6e617473,0x00000074,
    0x00050006,0x0000001e,0x00000000,0x61635375,0x0000656c,0x00060006,0x0000001e,0x00000001,
    0x61725475,0x616c736e,0x00006574,0x00030005,0x00000020,0x00006370,0x00040047,0x0000000b,
    0x0000001e,0x00000000,0x00040047,0x0000000f,0x0000001e,0x00000002,0x00040047,0x00000015,
    0x0000001e,0x00000001,0x00050048,0x00000019,0x00000000,0x0000000b,0x00000000,0x00030047,
    0x00000019,0x00000002,0x00040047,0x0000001c,0x0000001e,0x00000000,0x00050048,0x0000001e,
    0x00000000,0x00000023,0x00000000,0x00050048,0x0000001e,0x00000001,0x00000023,0x00000008,
    0x00030047,0x0000001e,0x00000002,0x00020013,0x00000002,0x00030021,0x00000003,0x00000002,
    0x00030016,0x00000006,0x00000020,0x00040017,0x00000007,0x00000006,0x00000004,0x00040017,
    0x00000008,0x00000006,0x00000002,0x0004001e,0x00000009,0x00000007,0x00000008,0x00040020,
    0x0000000a,0x00000003,0x00000009,0x0004003b,0x0000000a,0x0000000b,0x00000003,0x00040015,
    0x0000000c,0x00000020,0x00000001,0x0004002b,0x0000000c,0x0000000d,0x00000000,0x00040020,
    0x0000000e,0x00000001,0x00000007,0x0004003b,0x0000000e,0x0000000f,0x00000001,0x00040020,
    0x00000011,0x00000003,0x00000007,0x0004002b,0x0000000c,0x00000013,0x00000001,0x00040020,
    0x00000014,0x00000001,0x00000008,0x0004003b,0x00000014,0x00000015,0x00000001,0x00040020,
    0x00000017,0x00000003,0x00000008,0x0003001e,0x00000019,0x00000007,0x00040020,0x0000001a,
    0x00000003,0x00000019,0x0004003b,0x0000001a,0x0000001b,0x00000003,0x0004003b,0x00000014,
    0x0000001c,0x00000001,0x0004001e,0x0000001e,0x00000008,0x00000008,0x00040020,0x0000001f,
    0x00000009,0x0000001e,0x0004003b,0x0000001f,0x00000020,0x00000009,0x00040020,0x00000021,
    0x00000009,0x00000008,0x0004002b,0x00000006,0x00000028,0x00000000,0x0004002b,0x00000006,
    0x00000029,0x3f800000,0x00050036,0x00000002,0x00000004,0x00000000,0x00000003,0x000200f8,
    0x00000005,0x0004003d,0x00000007,0x00000010,0x0000000f,0x00050041,0x00000011,0x00000012,
    0x0000000b,0x0000000d,0x0003003e,0x00000012,0x00000010,0x0004003d,0x00000008,0x00000016,
    0x00000015,0x00050041,0x00000017,0x00000018,0x0000000b,0x00000013,0x0003003e,0x00000018,
    0x00000016,0x0004003d,0x00000008,0x0000001d,0x0000001c,0x00050041,0x00000021,0x00000022,
    0x00000020,0x0000000d,0x0004003d,0x00000008,0x00000023,0x00000022,0x00050085,0x00000008,
    0x00000024,0x0000001d,0x00000023,0x00050041,0x00000021,0x00000025,0x00000020,0x00000013,
    0x0004003d,0x00000008,0x00000026,0x00000025,0x00050081,0x00000008,0x00000027,0x00000024,
    0x00000026,0x00050051,0x00000006,0x0000002a,0x00000027,0x00000000,0x00050051,0x00000006,
    0x0000002b,0x00000027,0x00000001,0x00070050,0x00000007,0x0000002c,0x0000002a,0x0000002b,
    0x00000028,0x00000029,0x00050041,0x00000011,0x0000002d,0x0000001b,0x0000000d,0x0003003e,
    0x0000002d,0x0000002c,0x000100fd,0x00010038
];

// glsl_shader.frag, compiled with:
// # glslangValidator -V -x -o glsl_shader.frag.u32 glsl_shader.frag
/*
#version 450 core
layout(location = 0) out vec4 fColor;
layout(set=0, binding=0) uniform sampler2D sTexture;
layout(location = 0) in struct { vec4 Color; vec2 UV; } In;
void main()
{
    fColor = In.Color * texture(sTexture, In.UV.st);
}
*/
__glsl_shader_frag_spv := u32.[
    0x07230203,0x00010000,0x00080001,0x0000001e,0x00000000,0x00020011,0x00000001,0x0006000b,
    0x00000001,0x4c534c47,0x6474732e,0x3035342e,0x00000000,0x0003000e,0x00000000,0x00000001,
    0x0007000f,0x00000004,0x00000004,0x6e69616d,0x00000000,0x00000009,0x0000000d,0x00030010,
    0x00000004,0x00000007,0x00030003,0x00000002,0x000001c2,0x00040005,0x00000004,0x6e69616d,
    0x00000000,0x00040005,0x00000009,0x6c6f4366,0x0000726f,0x00030005,0x0000000b,0x00000000,
    0x00050006,0x0000000b,0x00000000,0x6f6c6f43,0x00000072,0x00040006,0x0000000b,0x00000001,
    0x00005655,0x00030005,0x0000000d,0x00006e49,0x00050005,0x00000016,0x78655473,0x65727574,
    0x00000000,0x00040047,0x00000009,0x0000001e,0x00000000,0x00040047,0x0000000d,0x0000001e,
    0x00000000,0x00040047,0x00000016,0x00000022,0x00000000,0x00040047,0x00000016,0x00000021,
    0x00000000,0x00020013,0x00000002,0x00030021,0x00000003,0x00000002,0x00030016,0x00000006,
    0x00000020,0x00040017,0x00000007,0x00000006,0x00000004,0x00040020,0x00000008,0x00000003,
    0x00000007,0x0004003b,0x00000008,0x00000009,0x00000003,0x00040017,0x0000000a,0x00000006,
    0x00000002,0x0004001e,0x0000000b,0x00000007,0x0000000a,0x00040020,0x0000000c,0x00000001,
    0x0000000b,0x0004003b,0x0000000c,0x0000000d,0x00000001,0x00040015,0x0000000e,0x00000020,
    0x00000001,0x0004002b,0x0000000e,0x0000000f,0x00000000,0x00040020,0x00000010,0x00000001,
    0x00000007,0x00090019,0x00000013,0x00000006,0x00000001,0x00000000,0x00000000,0x00000000,
    0x00000001,0x00000000,0x0003001b,0x00000014,0x00000013,0x00040020,0x00000015,0x00000000,
    0x00000014,0x0004003b,0x00000015,0x00000016,0x00000000,0x0004002b,0x0000000e,0x00000018,
    0x00000001,0x00040020,0x00000019,0x00000001,0x0000000a,0x00050036,0x00000002,0x00000004,
    0x00000000,0x00000003,0x000200f8,0x00000005,0x00050041,0x00000010,0x00000011,0x0000000d,
    0x0000000f,0x0004003d,0x00000007,0x00000012,0x00000011,0x0004003d,0x00000014,0x00000017,
    0x00000016,0x00050041,0x00000019,0x0000001a,0x0000000d,0x00000018,0x0004003d,0x0000000a,
    0x0000001b,0x0000001a,0x00050057,0x00000007,0x0000001c,0x00000017,0x0000001b,0x00050085,
    0x00000007,0x0000001d,0x00000012,0x0000001c,0x0003003e,0x00000009,0x0000001d,0x000100fd,
    0x00010038
];

//-----------------------------------------------------------------------------
// FUNCTIONS
//-----------------------------------------------------------------------------

// Backend data stored in io.BackendRendererUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
// FIXME: multi-context support is not tested and probably dysfunctional in this backend.
ImGui_ImplVulkan_GetBackendData :: () -> *ImGui_ImplVulkan_Data #no_context {
    if ImGui.GetCurrentContext() {
        return cast(*ImGui_ImplVulkan_Data) ImGui.GetIO().BackendRendererUserData;
    } else {
        return null;
    };
}

ImGui_ImplVulkan_MemoryType :: (properties: VkMemoryPropertyFlags, type_bits: u32) -> u32 #no_context {
    bd:   *ImGui_ImplVulkan_Data           = ImGui_ImplVulkan_GetBackendData();
    v:    *ImGui_ImplVulkan_InitInfo       = *bd.VulkanInitInfo;
    prop: VkPhysicalDeviceMemoryProperties = ---;
    vkGetPhysicalDeviceMemoryProperties(v.PhysicalDevice, *prop);
    for i: 0..prop.memoryTypeCount - 1 {
        if (prop.memoryTypes[i].propertyFlags & properties) == properties && type_bits & (1 << i) {
            return i;
        }
    }
    return 0xFFFFFFFF; // Unable to find memoryType
}

check_vk_result :: (err: VkResult) #no_context {
    if err != .SUCCESS {
        debug_break();
    }

    bd: *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();
    if !bd then return;
    v: *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    if v.CheckVkResultFn then v.CheckVkResultFn(err);
}

CreateOrResizeBuffer :: (
    buffer        : VkBuffer,
    buffer_memory : VkDeviceMemory,
    buffer_size   : VkDeviceSize,
    new_size      : u64,
    usage         : VkBufferUsageFlagBits
) -> (new_buffer: VkBuffer #must, new_buffer_memory: VkDeviceMemory #must, new_buffer_size: VkDeviceSize #must) #no_context {
    bd  : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v   : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    err : VkResult = ---;
    if buffer != VK_NULL_HANDLE {
        vkDestroyBuffer(v.Device, buffer, v.Allocator);
    }
    if buffer_memory != VK_NULL_HANDLE {
        vkFreeMemory(v.Device, buffer_memory, v.Allocator);
    }

    vertex_buffer_size_aligned : VkDeviceSize       = ((new_size - 1) / bd.BufferMemoryAlignment + 1) * bd.BufferMemoryAlignment;
    buffer_info                : VkBufferCreateInfo = .{
        size        = vertex_buffer_size_aligned,
        usage       = usage,
        sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
    };

    new_buffer : VkBuffer = ---;
    err = vkCreateBuffer(v.Device, *buffer_info, v.Allocator, *new_buffer);
    check_vk_result(err);

    req : VkMemoryRequirements;
    vkGetBufferMemoryRequirements(v.Device, new_buffer, *req);
    bd.BufferMemoryAlignment = ifx (bd.BufferMemoryAlignment > req.alignment) then bd.BufferMemoryAlignment else req.alignment;
    alloc_info := VkMemoryAllocateInfo.{
        allocationSize  = req.size,
        memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT, req.memoryTypeBits),
    };
    new_buffer_memory : VkDeviceMemory = ---;
    err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, *new_buffer_memory);
    check_vk_result(err);

    err = vkBindBufferMemory(v.Device, new_buffer, new_buffer_memory, 0);
    check_vk_result(err);
    new_buffer_size := req.size;

    return new_buffer, new_buffer_memory, new_buffer_size;
}

ImGui_ImplVulkan_SetupRenderState :: (
     draw_data      : *ImDrawData,
     pipeline       : VkPipeline,
     command_buffer : VkCommandBuffer,
     rb             : *ImGui_ImplVulkanH_FrameRenderBuffers,
     fb_width       : int,
     fb_height      : int
) #no_context {
    bd : *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();

    // Bind pipeline:
    {
        vkCmdBindPipeline(command_buffer, .VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
    }

    // Bind Vertex And Index Buffer:
    if draw_data.TotalVtxCount > 0 {
        vertex_buffers : [1]VkBuffer     = .[ rb.VertexBuffer ];
        vertex_offset  : [1]VkDeviceSize = .[ 0 ];
        vkCmdBindVertexBuffers(command_buffer, 0, xx vertex_buffers.count, vertex_buffers.data, vertex_offset.data);
        INDEX_TYPE : VkIndexType : ifx size_of(ImDrawIdx) == 2 then .VK_INDEX_TYPE_UINT16 else .VK_INDEX_TYPE_UINT32;
        vkCmdBindIndexBuffer(command_buffer, rb.IndexBuffer, 0, INDEX_TYPE);
    }

    // Setup viewport:
    {
        viewport := VkViewport.{
            x        = 0,
            y        = 0,
            width    = cast(float) fb_width,
            height   = cast(float) fb_height,
            minDepth = 0.0,
            maxDepth = 1.0,
        };
        vkCmdSetViewport(command_buffer, 0, 1, *viewport);
    }

    // Setup scale and translation:
    // Our visible imgui space lies from draw_data->DisplayPps (top left) to draw_data->DisplayPos+data_data->DisplaySize (bottom right). DisplayPos is (0,0) for single viewport apps.
    {
        scale := float.[
            2.0 / draw_data.DisplaySize.x,
            2.0 / draw_data.DisplaySize.y,
        ];
        translate := float.[
            -1.0 - draw_data.DisplayPos.x * scale[0],
            -1.0 - draw_data.DisplayPos.y * scale[1],
        ];
        vkCmdPushConstants(command_buffer, bd.PipelineLayout, .VK_SHADER_STAGE_VERTEX_BIT, size_of(float) * 0,           size_of(float) * scale.count,     scale.data);
        vkCmdPushConstants(command_buffer, bd.PipelineLayout, .VK_SHADER_STAGE_VERTEX_BIT, size_of(float) * scale.count, size_of(float) * translate.count, translate.data);
    }
}

ImGui_ImplVulkan_CreateShaderModules :: (device: VkDevice, allocator: *VkAllocationCallbacks) #no_context {
    // Create the shader modules
    bd: *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();

    if bd.ShaderModuleVert == VK_NULL_HANDLE {
        vert_info := VkShaderModuleCreateInfo.{};
        vert_info.sType    = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        vert_info.codeSize = size_of(type_of(__glsl_shader_vert_spv));
        vert_info.pCode    = __glsl_shader_vert_spv.data;
        err := vkCreateShaderModule(device, *vert_info, allocator, *bd.ShaderModuleVert);
        check_vk_result(err);
    }

    if bd.ShaderModuleFrag == VK_NULL_HANDLE {
        frag_info := VkShaderModuleCreateInfo.{};
        frag_info.sType    = .VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        frag_info.codeSize = size_of(type_of(__glsl_shader_frag_spv));
        frag_info.pCode    = __glsl_shader_frag_spv.data;
        err := vkCreateShaderModule(device, *frag_info, allocator, *bd.ShaderModuleFrag);
        check_vk_result(err);
    }
}

ImGui_ImplVulkan_CreatePipeline :: (device: VkDevice, allocator: *VkAllocationCallbacks, pipelineCache: VkPipelineCache, renderPass: VkRenderPass, MSAASamples: VkSampleCountFlagBits, pipeline: *VkPipeline, subpass: u32) #no_context {
    bd: *ImGui_ImplVulkan_Data = ImGui_ImplVulkan_GetBackendData();
    ImGui_ImplVulkan_CreateShaderModules(device, allocator);

    stage: [2]VkPipelineShaderStageCreateInfo;
    stage[0].sType  = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stage[0].stage  = .VK_SHADER_STAGE_VERTEX_BIT;
    stage[0].module = bd.ShaderModuleVert;
    stage[0].pName  = "main";
    stage[1].sType  = .VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stage[1].stage  = .VK_SHADER_STAGE_FRAGMENT_BIT;
    stage[1].module = bd.ShaderModuleFrag;
    stage[1].pName  = "main";

    binding_desc: [1]VkVertexInputBindingDescription;
    binding_desc[0].stride    = size_of(ImGui.ImDrawVert);
    binding_desc[0].inputRate = .VK_VERTEX_INPUT_RATE_VERTEX;

    attribute_desc: [3]VkVertexInputAttributeDescription;
    attribute_desc[0].location = 0;
    attribute_desc[0].binding  = binding_desc[0].binding;
    attribute_desc[0].format   = .VK_FORMAT_R32G32_SFLOAT;
    attribute_desc[0].offset   = cast(u32) IM_OFFSETOF(ImGui.ImDrawVert, #code pos);
    attribute_desc[1].location = 1;
    attribute_desc[1].binding  = binding_desc[0].binding;
    attribute_desc[1].format   = .VK_FORMAT_R32G32_SFLOAT;
    attribute_desc[1].offset   = cast(u32) IM_OFFSETOF(ImGui.ImDrawVert, #code uv);
    attribute_desc[2].location = 2;
    attribute_desc[2].binding  = binding_desc[0].binding;
    attribute_desc[2].format   = .VK_FORMAT_R8G8B8A8_UNORM;
    attribute_desc[2].offset   = cast(u32) IM_OFFSETOF(ImGui.ImDrawVert, #code col);

    vertex_info := VkPipelineVertexInputStateCreateInfo.{};
    vertex_info.sType                           = .VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertex_info.vertexBindingDescriptionCount   = cast(u32) binding_desc.count;
    vertex_info.pVertexBindingDescriptions      =           binding_desc.data;
    vertex_info.vertexAttributeDescriptionCount = cast(u32) attribute_desc.count;
    vertex_info.pVertexAttributeDescriptions    =           attribute_desc.data;

    ia_info := VkPipelineInputAssemblyStateCreateInfo.{};
    ia_info.sType    = .VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia_info.topology = .VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    viewport_info := VkPipelineViewportStateCreateInfo.{};
    viewport_info.sType         = .VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_info.viewportCount = 1;
    viewport_info.scissorCount  = 1;

    raster_info := VkPipelineRasterizationStateCreateInfo.{};
    raster_info.sType       = .VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    raster_info.polygonMode = .VK_POLYGON_MODE_FILL;
    raster_info.cullMode    = .VK_CULL_MODE_NONE;
    raster_info.frontFace   = .VK_FRONT_FACE_COUNTER_CLOCKWISE;
    raster_info.lineWidth   = 1.0;

    ms_info := VkPipelineMultisampleStateCreateInfo.{};
    ms_info.sType                = .VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms_info.rasterizationSamples = ifx MSAASamples != 0 then MSAASamples else .VK_SAMPLE_COUNT_1_BIT;

    color_attachment := VkPipelineColorBlendAttachmentState.{};
    color_attachment.blendEnable         = VK_TRUE;
    color_attachment.srcColorBlendFactor = .VK_BLEND_FACTOR_SRC_ALPHA;
    color_attachment.dstColorBlendFactor = .VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    color_attachment.colorBlendOp        = .VK_BLEND_OP_ADD;
    color_attachment.srcAlphaBlendFactor = .VK_BLEND_FACTOR_ONE;
    color_attachment.dstAlphaBlendFactor = .VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    color_attachment.alphaBlendOp        = .VK_BLEND_OP_ADD;
    color_attachment.colorWriteMask      = .VK_COLOR_COMPONENT_R_BIT | .VK_COLOR_COMPONENT_G_BIT | .VK_COLOR_COMPONENT_B_BIT | .VK_COLOR_COMPONENT_A_BIT;

    depth_info := VkPipelineDepthStencilStateCreateInfo.{};
    depth_info.sType = .VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;

    blend_info := VkPipelineColorBlendStateCreateInfo.{};
    blend_info.sType           = .VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    blend_info.attachmentCount = 1;
    blend_info.pAttachments    = *color_attachment;

    dynamic_states: [2]VkDynamicState = .[.VK_DYNAMIC_STATE_VIEWPORT, .VK_DYNAMIC_STATE_SCISSOR];
    dynamic_state := VkPipelineDynamicStateCreateInfo.{};
    dynamic_state.sType             = .VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic_state.dynamicStateCount = cast(u32) dynamic_states.count;
    dynamic_state.pDynamicStates    =           dynamic_states.data;

    info := VkGraphicsPipelineCreateInfo.{};
    info.sType               = .VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    info.flags               = bd.PipelineCreateFlags;
    info.stageCount          = cast(u32) stage.count;
    info.pStages             =           stage.data;
    info.pVertexInputState   = *vertex_info;
    info.pInputAssemblyState = *ia_info;
    info.pViewportState      = *viewport_info;
    info.pRasterizationState = *raster_info;
    info.pMultisampleState   = *ms_info;
    info.pDepthStencilState  = *depth_info;
    info.pColorBlendState    = *blend_info;
    info.pDynamicState       = *dynamic_state;
    info.layout              = bd.PipelineLayout;
    info.renderPass          = renderPass;
    info.subpass             = subpass;

//#ifdef IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING
    #if true {
        pipelineRenderingCreateInfo:= VkPipelineRenderingCreateInfoKHR.{};
        pipelineRenderingCreateInfo.sType                   = .VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
        pipelineRenderingCreateInfo.colorAttachmentCount    = 1;
        pipelineRenderingCreateInfo.pColorAttachmentFormats = *bd.VulkanInitInfo.ColorAttachmentFormat;
        if bd.VulkanInitInfo.UseDynamicRendering {
            info.pNext      = *pipelineRenderingCreateInfo;
            info.renderPass = VK_NULL_HANDLE; // Just make sure it's actually nullptr.
        }
    }
//#endif

    err := vkCreateGraphicsPipelines(device, pipelineCache, 1, *info, allocator, pipeline);
    check_vk_result(err);
}

ImGui_ImplVulkan_CreateDeviceObjects :: () -> bool #no_context {
    bd := ImGui_ImplVulkan_GetBackendData();
    v  := *bd.VulkanInitInfo;
    err: VkResult = ---;

    if !bd.FontSampler {
        // Bilinear sampling is required by default. Set 'io.Fonts->Flags |= ImFontAtlasFlags_NoBakedLines' or 'style.AntiAliasedLinesUseTex = false' to allow point/nearest sampling.
        info := VkSamplerCreateInfo.{};
        info.sType         = .VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
        info.magFilter     = .VK_FILTER_LINEAR;
        info.minFilter     = .VK_FILTER_LINEAR;
        info.mipmapMode    = .VK_SAMPLER_MIPMAP_MODE_LINEAR;
        info.addressModeU  = .VK_SAMPLER_ADDRESS_MODE_REPEAT;
        info.addressModeV  = .VK_SAMPLER_ADDRESS_MODE_REPEAT;
        info.addressModeW  = .VK_SAMPLER_ADDRESS_MODE_REPEAT;
        info.minLod        = -1000;
        info.maxLod        = 1000;
        info.maxAnisotropy = 1.0;
        err = vkCreateSampler(v.Device, *info, v.Allocator, *bd.FontSampler);
        check_vk_result(err);
    }

    if !bd.DescriptorSetLayout {
        binding: [1]VkDescriptorSetLayoutBinding;
        binding[0].descriptorType  = .VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        binding[0].descriptorCount = 1;
        binding[0].stageFlags      = .VK_SHADER_STAGE_FRAGMENT_BIT;
        info := VkDescriptorSetLayoutCreateInfo.{};
        info.sType        = .VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        info.bindingCount = cast(u32) binding.count;
        info.pBindings    =           binding.data;
        err = vkCreateDescriptorSetLayout(v.Device, *info, v.Allocator, *bd.DescriptorSetLayout);
        check_vk_result(err);
    }

    if !bd.PipelineLayout {
        // Constants: we are using 'vec2 offset' and 'vec2 scale' instead of a full 3d projection matrix
        push_constants: [1]VkPushConstantRange;
        push_constants[0].stageFlags = .VK_SHADER_STAGE_VERTEX_BIT;
        push_constants[0].offset = size_of(float) * 0;
        push_constants[0].size = size_of(float) * 4;
        set_layout: [1]VkDescriptorSetLayout = .[bd.DescriptorSetLayout];
        layout_info := VkPipelineLayoutCreateInfo.{};
        layout_info.sType                  = .VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        layout_info.setLayoutCount         = cast(u32) set_layout.count;
        layout_info.pSetLayouts            =           set_layout.data;
        layout_info.pushConstantRangeCount = cast(u32) push_constants.count;
        layout_info.pPushConstantRanges    =           push_constants.data;
        err = vkCreatePipelineLayout(v.Device, *layout_info, v.Allocator, *bd.PipelineLayout);
        check_vk_result(err);
    }

    ImGui_ImplVulkan_CreatePipeline(v.Device, v.Allocator, v.PipelineCache, bd.RenderPass, v.MSAASamples, *bd.Pipeline, bd.Subpass);

    return true;
}

ImGui_ImplVulkan_DestroyDeviceObjects :: () #no_context {
    bd : *ImGui_ImplVulkan_Data     = ImGui_ImplVulkan_GetBackendData();
    v  : *ImGui_ImplVulkan_InitInfo = *bd.VulkanInitInfo;
    ImGui_ImplVulkanH_DestroyWindowRenderBuffers(v.Device, *bd.MainWindowRenderBuffers, v.Allocator);
    ImGui_ImplVulkan_DestroyFontUploadObjects();

    if bd.ShaderModuleVert    { vkDestroyShaderModule(v.Device, bd.ShaderModuleVert, v.Allocator); bd.ShaderModuleVert = VK_NULL_HANDLE; }
    if bd.ShaderModuleFrag    { vkDestroyShaderModule(v.Device, bd.ShaderModuleFrag, v.Allocator); bd.ShaderModuleFrag = VK_NULL_HANDLE; }
    if bd.FontView            { vkDestroyImageView(v.Device, bd.FontView, v.Allocator); bd.FontView = VK_NULL_HANDLE; }
    if bd.FontImage           { vkDestroyImage(v.Device, bd.FontImage, v.Allocator); bd.FontImage = VK_NULL_HANDLE; }
    if bd.FontMemory          { vkFreeMemory(v.Device, bd.FontMemory, v.Allocator); bd.FontMemory = VK_NULL_HANDLE; }
    if bd.FontSampler         { vkDestroySampler(v.Device, bd.FontSampler, v.Allocator); bd.FontSampler = VK_NULL_HANDLE; }
    if bd.DescriptorSetLayout { vkDestroyDescriptorSetLayout(v.Device, bd.DescriptorSetLayout, v.Allocator); bd.DescriptorSetLayout = VK_NULL_HANDLE; }
    if bd.PipelineLayout      { vkDestroyPipelineLayout(v.Device, bd.PipelineLayout, v.Allocator); bd.PipelineLayout = VK_NULL_HANDLE; }
    if bd.Pipeline            { vkDestroyPipeline(v.Device, bd.Pipeline, v.Allocator); bd.Pipeline = VK_NULL_HANDLE; }
}

ImGui_ImplVulkanH_DestroyFrameRenderBuffers :: (
    device    : VkDevice ,
    buffers   : *ImGui_ImplVulkanH_FrameRenderBuffers,
    allocator : *VkAllocationCallbacks
) #no_context {
    if buffers.VertexBuffer       { vkDestroyBuffer(device, buffers.VertexBuffer, allocator); buffers.VertexBuffer = VK_NULL_HANDLE; }
    if buffers.VertexBufferMemory { vkFreeMemory(device, buffers.VertexBufferMemory, allocator); buffers.VertexBufferMemory = VK_NULL_HANDLE; }
    if buffers.IndexBuffer        { vkDestroyBuffer(device, buffers.IndexBuffer, allocator); buffers.IndexBuffer = VK_NULL_HANDLE; }
    if buffers.IndexBufferMemory  { vkFreeMemory(device, buffers.IndexBufferMemory, allocator); buffers.IndexBufferMemory = VK_NULL_HANDLE; }
    buffers.VertexBufferSize = 0;
    buffers.IndexBufferSize = 0;
}

ImGui_ImplVulkanH_DestroyWindowRenderBuffers :: (
    device    : VkDevice,
    buffers   : *ImGui_ImplVulkanH_WindowRenderBuffers,
    allocator : *VkAllocationCallbacks
) #no_context {
    for n : 0..buffers.Count - 1 {
        ImGui_ImplVulkanH_DestroyFrameRenderBuffers(device, *buffers.FrameRenderBuffers[n], allocator);
    }
    IM_FREE(buffers.FrameRenderBuffers);
    buffers.FrameRenderBuffers = null;
    buffers.Index              = 0;
    buffers.Count              = 0;
}

Basic :: #import "Basic";

IM_UNUSED :: (_ : $T) #no_context {

}

IM_ASSERT :: (condition: bool) #no_context {
    // @Todo
}

IM_OFFSETOF :: ($T: Type, $field: Code) -> u64 #no_context {
    obj: *T = null;
    return (cast(u64) *obj.#insert field) - (cast(u64) obj);
}

IM_ARRAYSIZE :: (arr: []$T) -> u64 #no_context {
    return cast(u64) arr.count;
}

IM_NEW :: ($T: Type) -> *T #no_context {
    obj : *T = ImGui.MemAlloc(size_of(T));
    obj.*    = .{};
    return obj;
}

IM_FREE :: (obj: *$T) #no_context {
    ImGui.MemFree(obj);
}

IM_DELETE :: (obj: *$T) #no_context {
    ImGui.MemFree(obj);
}

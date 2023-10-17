transition_image_layout :: (
    command_buffer : VkCommandBuffer,
    image          : VkImage,
    old_layout     : VkImageLayout,
    new_layout     : VkImageLayout
) {
    if old_layout == new_layout {
        return;
    }

    image_memory_barrier : VkImageMemoryBarrier = .{
        srcAccessMask       = .VK_ACCESS_MEMORY_WRITE_BIT,
        dstAccessMask       = .VK_ACCESS_MEMORY_READ_BIT,
        oldLayout           = old_layout,
        newLayout           = new_layout,
        srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        image               = image,
        subresourceRange    = .{
            aspectMask     = .VK_IMAGE_ASPECT_COLOR_BIT,
            baseMipLevel   = 0,
            levelCount     = VK_REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount     = VK_REMAINING_ARRAY_LAYERS,
        },
    };
    vkCmdPipelineBarrier(
        command_buffer,
        .VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        .VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        .VK_DEPENDENCY_BY_REGION_BIT,
        0,
        null,
        0,
        null,
        1,
        *image_memory_barrier
    );
}

transition_texture_layout :: inline (
    command_buffer : VkCommandBuffer,
    texture        : *Texture,
    new_layout     : VkImageLayout
) {
    transition_image_layout(command_buffer, texture.image, old_layout = texture.layout, new_layout = new_layout);
    texture.layout = new_layout;
}

copy_buffer_to_image :: inline (
    command_buffer : VkCommandBuffer,
    buffer         : VkBuffer,
    image          : VkImage,
    width          : u32,
    height         : u32,
    old_layout     : VkImageLayout
) {
    transition_image_layout(command_buffer, image, old_layout = old_layout, new_layout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    copy_buffer_to_image_no_barrier(command_buffer, buffer, image, width = width, height = height);
}

copy_buffer_to_texture :: inline (
    command_buffer : VkCommandBuffer,
    buffer         : VkBuffer,
    texture        : *Texture,
    width          : u32,
    height         : u32
) {
    transition_texture_layout(command_buffer, texture, new_layout = .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    copy_buffer_to_image_no_barrier(command_buffer, buffer, texture.image, width = width, height = height);
}

#scope_file

copy_buffer_to_image_no_barrier :: (
    command_buffer : VkCommandBuffer,
    buffer         : VkBuffer,
    image          : VkImage,
    width          : u32,
    height         : u32
) {
    region := VkBufferImageCopy.{
        bufferOffset      = 0,
        bufferRowLength   = 0,
        bufferImageHeight = 0,

        imageSubresource = .{
            aspectMask     = .VK_IMAGE_ASPECT_COLOR_BIT,
            mipLevel       = 0,
            baseArrayLayer = 0,
            layerCount     = 1,
        },

        imageOffset = .{0, 0, 0},
        imageExtent = .{
            width  = width,
            height = height,
            depth  = 1,
        },
    };
    vkCmdCopyBufferToImage(command_buffer, buffer, image, .VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, *region);
}

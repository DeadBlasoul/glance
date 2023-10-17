create_buffer :: (
    using this    : *RenderingContext, // @Todo/FIXME: do not pass the complete RenderingContext: too bug-prone
    size          : VkDeviceSize,
    usage         : VkBufferUsageFlags,
    properties    : VkMemoryPropertyFlags,
    buffer        : *VkBuffer,
    buffer_memory : *VkDeviceMemory
) {
    find_memory_type_index :: inline (using this : *RenderingContext, type_filter : u32, properties : VkMemoryPropertyFlags) -> u32 {
        memory_properties : VkPhysicalDeviceMemoryProperties = ---;
        vkGetPhysicalDeviceMemoryProperties(physical_device, *memory_properties);

        for ix : 0..memory_properties.memoryTypeCount - 1 {
            if type_filter & (1 << ix) && (memory_properties.memoryTypes[ix].propertyFlags & properties) == properties {
                return ix;
            }
        }

        Basic.assert(false, "The memory with required properties is not found");

        return cast,no_check(u32) -1;
    }

    buffer_create_info := VkBufferCreateInfo.{
        size        = size,
        usage       = usage,
        sharingMode = .VK_SHARING_MODE_EXCLUSIVE,
    };

    vk_call(vkCreateBuffer(device, *buffer_create_info, null, buffer));

    memory_requirements : VkMemoryRequirements = ---;
    vkGetBufferMemoryRequirements(device, buffer.*, *memory_requirements);

    allocation := VkMemoryAllocateInfo.{
        allocationSize  = memory_requirements.size,
        memoryTypeIndex = find_memory_type_index(this, memory_requirements.memoryTypeBits, properties),
    };
    vk_call(vkAllocateMemory(device, *allocation, null, buffer_memory));

    vkBindBufferMemory(device, buffer.*, buffer_memory.*, 0);
}

// @Todo/FIXME: do not pass the complete RenderingContext: too bug-prone
copy_memory :: (using this : *RenderingContext, source : *void, destination : VkDeviceMemory, size : VkDeviceSize) {
    destination_data : *void = ---;

    vkMapMemory(device, destination, 0, size, 0, *destination_data);
    memcpy(destination_data, source, cast(s64) size);
    vkUnmapMemory(device, destination);
}

// @Todo/FIXME: do not pass the complete RenderingContext: too bug-prone
copy_buffer :: (using this : *RenderingContext, source : VkBuffer, destination : VkBuffer, size : VkDeviceSize) {
    // @Warning: it's a very slow copying of the buffer, should accept buffer instead
    // @FIXME
    command_pool   := command_pools[0];
    command_buffer := begin_single_time_commands(device, command_pool);
    {
        copy_region := VkBufferCopy.{
            srcOffset = 0,
            dstOffset = 0,
            size      = size,
        };
        vkCmdCopyBuffer(command_buffer, source, destination, 1, *copy_region);
    }
    end_single_time_commands(command_buffer, device, command_pool, queue);
}

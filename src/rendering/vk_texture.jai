Texture :: struct {
    width  : u32;
    height : u32;
    image  : VkImage       = VK_NULL_HANDLE;
    layout : VkImageLayout = .VK_IMAGE_LAYOUT_UNDEFINED;
    rtv    : VkImageView   = VK_NULL_HANDLE;
}

create_texture :: inline (
    using this     : *RenderingContext,
    width          : u32,
    height         : u32,
    format         : VkFormat,
    tiling         : VkImageTiling,
    usage          : VkImageUsageFlags,
    properties     : VkMemoryPropertyFlags,
    texture        : *Texture,
    texture_memory : *VkDeviceMemory
) {
    create_image(device, physical_device, width = width, height = height, format, tiling, usage, properties, *texture.image, texture_memory);
    create_image_view(device, format, texture.image, *texture.rtv);

    texture.width  = width;
    texture.height = height;
    texture.layout = .VK_IMAGE_LAYOUT_UNDEFINED;
}

destroy_texture :: inline (device: VkDevice, texture: *Texture) {
    vkDestroyImageView(device, texture.rtv, null);
    vkDestroyImage(device, texture.image, null);
}

#scope_file

// @Cleanup: move away allocation from image creating
create_image :: (
    device          : VkDevice,
    physical_device : VkPhysicalDevice,
    width           : u32,
    height          : u32,
    format          : VkFormat,
    tiling          : VkImageTiling,
    usage           : VkImageUsageFlags,
    properties      : VkMemoryPropertyFlags,
    image           : *VkImage,
    image_memory    : *VkDeviceMemory // @Todo: should it be here?
) {
    find_memory_type_index :: inline (physical_device: VkPhysicalDevice, type_filter : u32, properties : VkMemoryPropertyFlags) -> u32 {
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

    image_info := VkImageCreateInfo.{
        imageType     = .VK_IMAGE_TYPE_2D,
        extent        = .{
            width  = width,
            height = height,
            depth  = 1,
        },
        mipLevels     = 1,
        arrayLayers   = 1,
        format        = format,
        tiling        = tiling,
        initialLayout = .VK_IMAGE_LAYOUT_UNDEFINED,
        usage         = usage,
        samples       = .VK_SAMPLE_COUNT_1_BIT,
        flags         = 0,
        sharingMode   = .VK_SHARING_MODE_EXCLUSIVE,
    };
    vk_call(vkCreateImage(device, *image_info, null, image));

    memory_requirements : VkMemoryRequirements = ---;
    vkGetImageMemoryRequirements(device, image.*, *memory_requirements);

    allocation := VkMemoryAllocateInfo.{
        allocationSize  = memory_requirements.size,
        memoryTypeIndex = find_memory_type_index(physical_device, memory_requirements.memoryTypeBits, properties),
    };
    vk_call(vkAllocateMemory(device, *allocation, null, image_memory));

    vkBindImageMemory(device, image.*, image_memory.*, 0);
}

create_image_view :: (device: VkDevice, format: VkFormat, image: VkImage, image_view: *VkImageView) {
    image_view_create_info := VkImageViewCreateInfo.{
        image      = image,
        viewType   = .VK_IMAGE_VIEW_TYPE_2D,
        format     = format,
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
    vk_call(vkCreateImageView(device, *image_view_create_info, null, image_view));
}

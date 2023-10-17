
VulkanRuntimeDependency :: struct {
    layers : struct {
        required : struct {
            #if GPU_DEBUG {
                validation : void; @VK_LAYER_KHRONOS_validation;
            }
        };

        optional : struct {
            // Nothing at the moment
        };
    };

    using extension : struct {
        using instance : struct {

        };
    };
}
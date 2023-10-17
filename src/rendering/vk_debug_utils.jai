vk_call :: ($strict : bool = true, $code : Code) -> VkResult #expand #no_debug {
    result : VkResult = #insert code;

    #if GPU_DEBUG {
        EXPRESSION_STRING :: #run code_to_string(code);
        #if strict {
            is_failure := result != .SUCCESS;
        } else {
            is_failure := result < 0;
        }

        if is_failure {
            Basic.print("VULKAN: Invocation of '%' did not succeed with %.\n", EXPRESSION_STRING, result);
            Basic.exit(1);
        }
    }

    return result;
}

vk_call :: ($code : Code) -> VkResult #expand #no_debug {
    return vk_call(strict = true, code);
}

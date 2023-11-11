#scope_module

imgui_create_fonts_texture :: (using this : *RenderingContext) {
    command_pool   := command_pools[0];
    command_buffer := begin_single_time_commands(device, command_pool);
    {
        ImGui_ImplVulkan_CreateFontsTexture(command_buffer);
    }
    end_single_time_commands(command_buffer, device, command_pool, queue);
    ImGui_ImplVulkan_DestroyFontUploadObjects();
}

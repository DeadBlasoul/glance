TODO list for the engine features and included demos.

### Engine

- Runtime
  - FileSystem
    - [ ] Executable path discovery
    - [ ] Ability to ignore the current working directory in respect to executable path
- Building
  - [ ] Simplify build variants to release, development
  - [ ] Simplify build flags 
  - [ ] Make compiler backend selection be available in any build variant
- Shaders Hot-Reload:
  - [x] Initial support
  - [ ] Cleanup
- ImGui:
  - Input:
    - [x] Integrate default Win32 backend: imgui_impl_win32
  - Rendering:
    - [x] Integrate default Vulkan backend: imgui_imlp_vulkan  
          Note: Rewritten in JAI; some places use engine primitives already.
    - [ ] Write a custom backend for rendering: imgui_impl_glance
- Debug System:
  - [ ] Game data and objects tracking
- Third Party Libraries
  - [ ] Discovery system
  - [ ] Automatic building (if required)

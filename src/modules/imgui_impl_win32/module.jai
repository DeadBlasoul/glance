ImGui_ImplWin32_Init :: (hwnd: *void) -> bool #foreign imgui_impl_win32 "?ImGui_ImplWin32_Init@@YA_NPEAX@Z";
ImGui_ImplWin32_InitForOpenGL :: (hwnd: *void) -> bool #foreign imgui_impl_win32 "?ImGui_ImplWin32_InitForOpenGL@@YA_NPEAX@Z";
ImGui_ImplWin32_Shutdown :: () #foreign imgui_impl_win32 "?ImGui_ImplWin32_Shutdown@@YAXXZ";
ImGui_ImplWin32_NewFrame :: () #foreign imgui_impl_win32 "?ImGui_ImplWin32_NewFrame@@YAXXZ";
ImGui_ImplWin32_WndProcHandler :: (hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT #foreign imgui_impl_win32 "?ImGui_ImplWin32_WndProcHandler@@YA_JPEAUHWND__@@I_K_J@Z";

// DPI-related helpers (optional)
// - Use to enable DPI awareness without having to create an application manifest.
// - Your own app may already do this via a manifest or explicit calls. This is mostly useful for our examples/ apps.
// - In theory we could call simple functions from Windows SDK such as SetProcessDPIAware(), SetProcessDpiAwareness(), etc.
//   but most of the functions provided by Microsoft require Windows 8.1/10+ SDK at compile time and Windows 8/10+ at runtime,
//   neither we want to require the user to have. So we dynamically select and load those functions to avoid dependencies.
ImGui_ImplWin32_EnableDpiAwareness :: () #foreign imgui_impl_win32 "?ImGui_ImplWin32_EnableDpiAwareness@@YAXXZ";
ImGui_ImplWin32_GetDpiScaleForHwnd :: (hwnd: HWND) -> float #foreign imgui_impl_win32 "?ImGui_ImplWin32_GetDpiScaleForHwnd@@YAMPEAX@Z";
ImGui_ImplWin32_GetDpiScaleForMonitor :: (monitor: HMONITOR) -> float #foreign imgui_impl_win32 "?ImGui_ImplWin32_GetDpiScaleForMonitor@@YAMPEAX@Z";

// Transparency related helpers (optional) [experimental]
// - Use to enable alpha compositing transparency with the desktop.
// - Use together with e.g. clearing your framebuffer with zero-alpha.
ImGui_ImplWin32_EnableAlphaCompositing :: (hwnd: HWND) #foreign imgui_impl_win32 "?ImGui_ImplWin32_EnableAlphaCompositing@@YAXPEAX@Z";

#scope_module

UINT :: u32;

ImGui :: #import "ImGui";
         #import "Windows";

imgui_impl_win32 :: #library,no_dll "imgui_impl_win32";

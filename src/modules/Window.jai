#scope_export

#assert OS == .WINDOWS, "The current module supports only Windows for now";

Window :: struct {
    jai_context : *Context;

    width       : u32;
    height      : u32;
    is_closed   : bool;
    is_resized  : bool;

    handle            : HWND;
    saved_window_info : SavedWindowInfo;
    lock              : Thread.Mutex;
}

WindowCreateInfo :: struct {
    jai_context : *Context;
    title       : string;
    width       : u32;
    height      : u32;
}

WindowFlag :: enum {
    IS_CLOSED;
    IS_RESIZED;
}

WindowError :: enum {
    SUCCESS :: 0;
    WIN32_CANNOT_CREATE_WINDOW_CLASS;
}

create_window :: (using window_create_info : *WindowCreateInfo, window : *Window) {
    Basic.assert(jai_context != null);

    window.jai_context = jai_context;
    window.width       = width;
    window.height      = height;

    Thread.init(*window.lock); // @TODO: Come up some name for the mutex

    rect_width  := cast(s32) width;
    rect_height := cast(s32) height;
    {
        window_rect := RECT.{ 0, 0, rect_width, rect_height };

        if AdjustWindowRect(*window_rect, WS_OVERLAPPEDWINDOW, cast(BOOL) false) {
            rect_width  = window_rect.right - window_rect.left;
            rect_height = window_rect.bottom - window_rect.top;
        }
    }

    win32_application_instance := GetModuleHandleW(null);

    error := create_window_class(win32_application_instance);
    if error {
        // @TODO: expose error via return value
        Basic.print("[---] Cannot create window: %\n", error);
        Basic.exit(1);
    }

    new_window_handle := CreateWindowExW(
        dwExStyle    = 0,
        lpClassName  = WIN32_WINDOW_CLASS_NAME.data,
        lpWindowName = utf8_to_wide(title),
        dwStyle      = WS_OVERLAPPEDWINDOW,

        // Size and position
        x       = CW_USEDEFAULT,
        y       = CW_USEDEFAULT,
        nWidth  = rect_width,
        nHeight = rect_height,

        hwndParent = null,
        hMenu      = null,
        hInstance  = win32_application_instance,
        lpParam    = null
    );
    if !new_window_handle {
        // @TODO: expose error via return value
        Basic.print("[---] Cannot create window: %\n", GetLastError());
        Basic.exit(1);
    }

    window.handle = new_window_handle;
    SetWindowLongPtrW(window.handle, GWLP_USERDATA, cast,no_check(LONG_PTR) window);

    content, success := File.read_entire_file(SAVED_WINDOW_PLACEMENT_FILE_NAME);
    if success {
        window_placement := cast(*WINDOWPLACEMENT) content.data;
        SetWindowPlacement(window.handle, window_placement);
        ShowWindow(window.handle, cast(s32) window_placement.showCmd);
    } else {
        ShowWindow(window.handle, SW_NORMAL);
    }
}

close_window :: (window : *Window) {
    Thread.destroy(*window.lock);
}

run :: (window : *Window) {
    poll_window_events :: (window : *Window) -> bool {
        msg : MSG;

        while PeekMessageW(*msg, window.handle, 0, 0, PM_REMOVE) {
            TranslateMessage(*msg);
            DispatchMessageW(*msg);
        }

        return !window.is_closed;
    }

    while poll_window_events(window) {
        // window.is_resized = false; // TODO: DELETE ME
        /* ... */
    }
}


toggle_fullscreen :: (window : *Window, desire_fullscreen : bool) -> (success: bool, width: s32, height: s32) {

}

consume_window_flag :: inline (window : *Window, $flag : WindowFlag) #no_context {
    set_window_flag(window, flag, false);
}

post_window_flag :: inline (window : *Window, $flag : WindowFlag) #no_context {
    set_window_flag(window, flag, true);
}

set_window_flag :: inline (window : *Window, $flag : WindowFlag, value : bool) #no_context {
    #if flag == .IS_RESIZED {
        window.is_resized = value;
    } else #if flag == .IS_CLOSED {
        window.is_closed = value;
    }
}

#scope_file

SavedWindowInfo :: struct {
    rect     : RECT;
    style    : s32;
    ex_style : s32;
}

create_window_class :: (win32_application_instance: *void) -> (error : WindowError) {
    window_class := WNDCLASSEXW.{
        cbSize        = size_of(WNDCLASSEXW),
        style         = CS_VREDRAW | CS_HREDRAW | CS_OWNDC,
        lpfnWndProc   = xx window_procedure,
        cbClsExtra    = 0,
        cbWndExtra    = 0,
        hInstance     = win32_application_instance,
        hIcon         = LoadIconW(win32_application_instance, IDI_APPLICATION),
        hCursor       = LoadCursorW(win32_application_instance, IDC_ARROW),
        hbrBackground = null,
        lpszMenuName  = null,
        lpszClassName = WIN32_WINDOW_CLASS_NAME.data,
    };

    //
    // The Windows holds the info about registered classes itself, so we just do a yolo registration for the new one class.
    //
    if !RegisterClassExW(*window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS {
        return .WIN32_CANNOT_CREATE_WINDOW_CLASS;
    } else {
        return .SUCCESS;
    }
}

// @Todo: this was used to debug windows messages; maybe we should save it somewhere...
WindowMessage :: enum {
    WM_NULL ::0x0000;
    WM_CREATE :: 0x0001;
    WM_DESTROY :: 0x0002;
    WM_MOVE :: 0x0003;

    WM_SIZE                         :: 0x0005;
    WM_SETFOCUS                     :: 0x0007;
    WM_KILLFOCUS                    :: 0x0008;
    WM_ENABLE                       :: 0x000A;
    WM_SETREDRAW                    :: 0x000B;
    WM_SETTEXT                      :: 0x000C;
    WM_GETTEXT                      :: 0x000D;
    WM_GETTEXTLENGTH                :: 0x000E;
    WM_PAINT                        :: 0x000F;
    WM_CLOSE                        :: 0x0010;
    WM_QUERYENDSESSION              :: 0x0011;
    WM_QUERYOPEN                    :: 0x0013;
    WM_ENDSESSION                   :: 0x0016;
    WM_QUIT                         :: 0x0012;
    WM_ERASEBKGND                   :: 0x0014;
    WM_SYSCOLORCHANGE               :: 0x0015;
    WM_SHOWWINDOW                   :: 0x0018;
    WM_WININICHANGE                 :: 0x001A;
    WM_SETTINGCHANGE                :: WM_WININICHANGE;
    WM_DEVMODECHANGE                :: 0x001B;
    WM_ACTIVATEAPP                  :: 0x001C;
    WM_FONTCHANGE                   :: 0x001D;
    WM_TIMECHANGE                   :: 0x001E;
    WM_CANCELMODE                   :: 0x001F;
    WM_SETCURSOR                    :: 0x0020;
    WM_MOUSEACTIVATE                :: 0x0021;
    WM_CHILDACTIVATE                :: 0x0022;
    WM_QUEUESYNC                    :: 0x0023;
    WM_GETMINMAXINFO                :: 0x0024;

    WM_NOTIFY                       :: 0x004E;
    WM_INPUTLANGCHANGEREQUEST       :: 0x0050;
    WM_INPUTLANGCHANGE              :: 0x0051;
    WM_TCARD                        :: 0x0052;
    WM_HELP                         :: 0x0053;
    WM_USERCHANGED                  :: 0x0054;
    WM_NOTIFYFORMAT                 :: 0x0055;
    WM_CONTEXTMENU                  :: 0x007B;
    WM_STYLECHANGING                :: 0x007C;
    WM_STYLECHANGED                 :: 0x007D;
    WM_DISPLAYCHANGE                :: 0x007E;
    WM_GETICON                      :: 0x007F;
    WM_SETICON                      :: 0x0080;
    WM_NCCREATE                     :: 0x0081;
    WM_NCDESTROY                    :: 0x0082;
    WM_NCCALCSIZE                   :: 0x0083;
    WM_NCHITTEST                    :: 0x0084;
    WM_NCPAINT                      :: 0x0085;
    WM_NCACTIVATE                   :: 0x0086;
    WM_GETDLGCODE                   :: 0x0087;
    WM_SYNCPAINT                    :: 0x0088;
    WM_NCMOUSEMOVE                  :: 0x00A0;
    WM_NCLBUTTONDOWN                :: 0x00A1;
    WM_NCLBUTTONUP                  :: 0x00A2;
    WM_NCLBUTTONDBLCLK              :: 0x00A3;
    WM_NCRBUTTONDOWN                :: 0x00A4;
    WM_NCRBUTTONUP                  :: 0x00A5;
    WM_NCRBUTTONDBLCLK              :: 0x00A6;
    WM_NCMBUTTONDOWN                :: 0x00A7;
    WM_NCMBUTTONUP                  :: 0x00A8;
    WM_NCMBUTTONDBLCLK              :: 0x00A9;
    WM_NCXBUTTONDOWN                :: 0x00AB;
    WM_NCXBUTTONUP                  :: 0x00AC;
    WM_NCXBUTTONDBLCLK              :: 0x00AD;
    WM_INPUT_DEVICE_CHANGE          :: 0x00FE;
    WM_INPUT                        :: 0x00FF;
    WM_KEYFIRST                     :: 0x0100;
    WM_KEYDOWN                      :: 0x0100;
    WM_KEYUP                        :: 0x0101;
    WM_CHAR                         :: 0x0102;
    WM_DEADCHAR                     :: 0x0103;
    WM_SYSKEYDOWN                   :: 0x0104;
    WM_SYSKEYUP                     :: 0x0105;
    WM_SYSCHAR                      :: 0x0106;
    WM_SYSDEADCHAR                  :: 0x0107;
    WM_UNICHAR                      :: 0x0109;
    WM_KEYLAST                      :: 0x0109;
    UNICODE_NOCHAR                  :: 0xFFFF;
    WM_IME_STARTCOMPOSITION         :: 0x010D;
    WM_IME_ENDCOMPOSITION           :: 0x010E;
    WM_IME_COMPOSITION              :: 0x010F;
    WM_IME_KEYLAST                  :: 0x010F;
    WM_INITDIALOG                   :: 0x0110;
    WM_COMMAND                      :: 0x0111;
    WM_SYSCOMMAND                   :: 0x0112;
    WM_TIMER                        :: 0x0113;
    WM_HSCROLL                      :: 0x0114;
    WM_VSCROLL                      :: 0x0115;
    WM_INITMENU                     :: 0x0116;
    WM_INITMENUPOPUP                :: 0x0117;
    WM_GESTURE                      :: 0x0119;
    WM_GESTURENOTIFY                :: 0x011A;
    WM_MENUSELECT                   :: 0x011F;
    WM_MENUCHAR                     :: 0x0120;
    WM_ENTERIDLE                    :: 0x0121;
    WM_MENURBUTTONUP                :: 0x0122;
    WM_MENUDRAG                     :: 0x0123;
    WM_MENUGETOBJECT                :: 0x0124;
    WM_UNINITMENUPOPUP              :: 0x0125;
    WM_MENUCOMMAND                  :: 0x0126;
    WM_CHANGEUISTATE                :: 0x0127;
    WM_UPDATEUISTATE                :: 0x0128;
    WM_QUERYUISTATE                 :: 0x0129;

    WM_CTLCOLORMSGBOX               :: 0x0132;
    WM_CTLCOLOREDIT                 :: 0x0133;
    WM_CTLCOLORLISTBOX              :: 0x0134;
    WM_CTLCOLORBTN                  :: 0x0135;
    WM_CTLCOLORDLG                  :: 0x0136;
    WM_CTLCOLORSCROLLBAR            :: 0x0137;
    WM_CTLCOLORSTATIC               :: 0x0138;
    MN_GETHMENU                     :: 0x01E1;
    WM_MOUSEFIRST                   :: 0x0200;
    WM_MOUSEMOVE                    :: 0x0200;
    WM_LBUTTONDOWN                  :: 0x0201;
    WM_LBUTTONUP                    :: 0x0202;
    WM_LBUTTONDBLCLK                :: 0x0203;
    WM_RBUTTONDOWN                  :: 0x0204;
    WM_RBUTTONUP                    :: 0x0205;
    WM_RBUTTONDBLCLK                :: 0x0206;
    WM_MBUTTONDOWN                  :: 0x0207;
    WM_MBUTTONUP                    :: 0x0208;
    WM_MBUTTONDBLCLK                :: 0x0209;
    WM_MOUSEWHEEL                   :: 0x020A;
    WM_XBUTTONDOWN                  :: 0x020B;
    WM_XBUTTONUP                    :: 0x020C;
    WM_XBUTTONDBLCLK                :: 0x020D;
    WM_MOUSEHWHEEL                  :: 0x020E;
    WM_MOUSELAST                    :: 0x020E;

    WM_SIZING                       :: 0x0214;
    WM_EXITSIZEMOVE                 :: 0x0232;
    WM_DROPFILES                    :: 0x0233;
    WM_DPICHANGED                   :: 0x02E0;
}

SAVED_WINDOW_PLACEMENT_FILE_NAME :: "saved_window_placement.bin";

window_procedure :: (hwnd: HWND, msg: u32, w_param: WPARAM, l_param: LPARAM) -> LRESULT #c_call {
    if ImGui_ImplWin32_WndProcHandler(hwnd, msg, w_param, l_param) {
        return 1;
    }

    window := cast,no_check(*Window) GetWindowLongPtrA(hwnd, GWLP_USERDATA);

    if msg == {
        case WM_CLOSE; push_context window.jai_context {
            placement := WINDOWPLACEMENT.{
                length = size_of(WINDOWPLACEMENT),
            };

            if GetWindowPlacement(hwnd, *placement) then File.write_entire_file(SAVED_WINDOW_PLACEMENT_FILE_NAME, *placement, placement.length);

            post_window_flag(window, .IS_CLOSED);
        }

        case WM_SIZE; push_context window.jai_context {
            Thread.lock(*window.lock); defer Thread.unlock(*window.lock);

            window.width  = LOWORD(l_param);
            window.height = HIWORD(l_param);
            post_window_flag(window, .IS_RESIZED);

            return 0;
        }
    }

    return DefWindowProcW(hwnd, msg, w_param, l_param);
}

utf8_to_wide_array :: ($s : string) -> [s.count + 1]u16 {
    result : [s.count + 1]u16 = ---;

    converted, _, length_in_bytes := utf8_to_wide(s);
    Basic.assert(length_in_bytes == size_of(type_of(result)) - size_of(u16) /* <-- termination zero word */ );

    memcpy(result.data, converted, length_in_bytes);
    result[s.count] = 0;

    return result;
}

WM_ENTERSIZEMOVE :: 0x0231;
WM_EXITSIZEMOVE  :: 0x0232;

LONG_PTR        :: s64;
WINDOWPLACEMENT :: struct {
    length           : u32;
    flags            : u32;
    showCmd          : u32;
    ptMinPosition    : POINT;
    ptMaxPosition    : POINT;
    rcNormalPosition : RECT;
    rcDevice         : RECT;
}

IDI_APPLICATION            :: cast,no_check(*u16) 32512;
GWLP_USERDATA              :: cast(s32) -21;
ERROR_CLASS_ALREADY_EXISTS :: cast(OS_Error_Code) 1410;

WIN32_WINDOW_CLASS_NAME :: #run utf8_to_wide_array("VK_RENDERER_WINDOW_CLASS");

LOWORD :: (value : s64) -> u16 #no_context { return cast(u16) (value & 0xFFFF); }
HIWORD :: (value : s64) -> u16 #no_context { return cast(u16) (value >> 16); }

GetWindowLongPtrA :: (
    hWnd   : HWND,
    nIndex : s32
) -> LONG_PTR #foreign user32;

SetWindowLongPtrA :: (
    hWnd      : HWND,
    nIndex    : s32,
    dwNewLong : LONG_PTR
) -> LONG_PTR #foreign user32;

GetWindowPlacement :: (
    hWnd    : HWND,
    lpwndpl : *WINDOWPLACEMENT
) -> BOOL #foreign user32;

SetWindowPlacement :: (
    hWnd    : HWND,
    lpwndpl : *WINDOWPLACEMENT
) -> BOOL #foreign user32;

user32 :: #system_library "User32";

Basic  :: #import "Basic";
Thread :: #import "Thread";
          #import "Windows";
          #import "Windows_Utf8";
File   :: #import "File";
          #import "imgui_impl_win32";

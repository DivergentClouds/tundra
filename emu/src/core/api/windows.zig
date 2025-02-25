const std = @import("std");

pub const BOOL = std.os.windows.BOOL;
pub const WORD = std.os.windows.WORD;
pub const DWORD = std.os.windows.DWORD;
pub const CHAR = std.os.windows.CHAR;
pub const WCHAR = std.os.windows.WCHAR;
pub const HANDLE = std.os.windows.HANDLE;
pub const COORD = std.os.windows.COORD;
pub const UINT = std.os.windows.UINT;

pub const INPUT_RECORD = extern struct {
    EventType: DWORD,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        MouseEvent: MOUSE_EVENT_RECORD,
        WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
        MenuEvent: MENU_EVENT_RECORD,
        FocusEvent: FOCUS_EVENT_RECORD,
    },
};

pub const KEY_EVENT_RECORD = extern struct {
    bKeyDown: BOOL,
    wRepeatCount: WORD,
    wVirtualKeyCode: WORD,
    wVirtualScanCode: WORD,
    uChar: extern union {
        UnicodeChar: WCHAR,
        AsciiChar: CHAR,
    },
    dwControlKeyState: DWORD,
};

pub const EventKinds = enum(DWORD) {
    key_event = 0x01,
    mouse_event = 0x02,
    window_buffer_size = 0x04,
    menu_event = 0x08,
    focus_event = 0x10,
    _,
};

const MOUSE_EVENT_RECORD = extern struct {
    dwMousePosition: COORD,
    dwButtonState: DWORD,
    dwControlKeyState: DWORD,
    dwEventFlags: DWORD,
};

const WINDOW_BUFFER_SIZE_RECORD = extern struct {
    dwSize: COORD,
};
const MENU_EVENT_RECORD = extern struct {
    dwCommandId: UINT,
};
const FOCUS_EVENT_RECORD = extern struct {
    bSetFocus: BOOL,
};

pub extern "kernel32" fn GetNumberOfConsoleInputEvents(
    hConsoleInput: HANDLE,
    lpcNumberOfEvents: ?*DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn PeekConsoleInputA(
    hConsoleInput: HANDLE,
    lpBuffer: ?[*]INPUT_RECORD,
    nLength: DWORD,
    lpNumberOfEventsRead: ?*DWORD,
) callconv(.winapi) BOOL;

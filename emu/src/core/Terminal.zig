const std = @import("std");
const builtin = @import("builtin");

const Terminal = @This();

const DWord = std.os.windows.DWORD;

const OriginalTerminal = union {
    /// posix only
    termios: std.posix.termios,
    /// windows only
    mode: struct {
        in: DWord,
        out: DWord,
    },
};

const PollKinds = enum { stdin };

original: OriginalTerminal,
poller: std.io.Poller(PollKinds),
debug_input_fifo: ?std.fifo.LinearFifo(u8, .Dynamic),

const InputByte = enum(u8) {
    up = 'i' + 0x80,
    down = 'k' + 0x80,
    left = 'j' + 0x80,
    right = 'l' + 0x80,
    insert = 'n' + 0x80,
    delete = 'x' + 0x80,
    home = 'h' + 0x80,
    end = 'e' + 0x80,
};

const OutputByte = enum(u8) {
    backspace = 0x08, // equivalent to cursor_left + space + cursor_left
    line_feed = 0x0a, // cursor_down + scroll
    carriage_return = 0x0d, // set cursor to an x position of 0
    clear_right = 'R' + 0x80, // clear to the right of the cursor
    clear_below = 'B' + 0x80, // clear all lines below the cursor
    clear_all = 'X' + 0x80, // clear the whole screen
    reset_cursor = 'H' + 0x80, // set cursor to 0, 0
    cursor_up = 'i' + 0x80, // does not scroll
    cursor_down = 'k' + 0x80, // does not scroll
    cursor_left = 'j' + 0x80, // does not scroll
    cursor_right = 'l' + 0x80, // does not scroll
    _,
};

pub fn inputReady(terminal: *Terminal) !bool {
    if (terminal.debug_input_fifo) |fifo| {
        return fifo.readableLength() > 0;
    } else {
        // FIXME: hangs on windows due to an stdlib bug D:
        // https://github.com/ziglang/zig/issues/22991
        if (builtin.os.tag == .windows) {
            return error.PollBrokenOnWindows;
        }

        _ = try terminal.poller.pollTimeout(1);
        return terminal.poller.fifo(.stdin).readableLength() > 0;
    }
}

pub fn readChar(terminal: *Terminal) !u16 {
    if (try terminal.readCharInner()) |byte| {
        if (byte == 0x1b) {
            var sequence_array: [3]u8 = undefined;
            var index: usize = 0;

            while (try terminal.readCharInner()) |byte_inner| {
                if (index >= 3)
                    break;

                switch (byte_inner) {
                    '2', '3', '[', 'O' => {
                        sequence_array[index] = byte_inner;
                        index += 1;
                    },
                    'A'...'D', 'F', 'H', '~' => {
                        sequence_array[index] = byte_inner;
                        index += 1;
                        break;
                    },
                    else => {},
                }
            }

            const sequence = sequence_array[0..index];

            var opt_char: ?InputByte = null;

            if (sequence.len > 1) {
                if (sequence[0] == '[' or sequence[0] == 'O') {
                    opt_char = switch (sequence[1]) {
                        'A' => .up,
                        'B' => .down,
                        'C' => .right,
                        'D' => .left,
                        else => null,
                    };
                }

                if (sequence[0] == '[') {
                    if (sequence.len == 3 and sequence[2] == '~') {
                        opt_char = switch (sequence[1]) {
                            '2' => .insert,
                            '3' => .delete,
                            else => null,
                        };
                    } else {
                        opt_char = switch (sequence[1]) {
                            'H' => .home,
                            'F' => .end,
                            else => null,
                        };
                    }
                }
            }

            if (opt_char) |char| {
                return @intFromEnum(char);
            } else {
                return 0xffff;
            }
        }

        return switch (byte) {
            0x7f => 0x08,
            '\n' => '\r',
            '\r', '\t', 0x08 => byte,
            else => switch (byte) {
                0...0x1f => 0xffff,
                else => byte,
            },
        };
    } else return 0xffff;
}

fn readCharInner(terminal: *Terminal) !?u8 {
    if (try terminal.inputReady()) {
        if (terminal.debug_input_fifo) |*fifo| {
            return fifo.readItem().?; // can't be null due to the check in inputReady
        } else {
            return terminal.poller.fifo(.stdin).readItem().?; // can't be null because we polled in inputReady
        }
    }
    return null;
}

pub fn writeChar(byte: u8) !void {
    const stdout = std.io.getStdOut().writer();

    const char: OutputByte = @enumFromInt(byte);
    switch (char) {
        .backspace => try stdout.writeAll("\x08 \x08"), // erasing backspace in a cross platform way
        .line_feed => try stdout.writeByte('\n'),
        .carriage_return => try stdout.writeByte('\r'),
        .clear_right => try stdout.writeAll("\x1b[K"),
        .clear_below => try stdout.writeAll("\x1b[J"),
        .clear_all => try stdout.writeAll("\x1b[2J"),
        .reset_cursor => try stdout.writeAll("\x1b[;H"),
        .cursor_up => try stdout.writeAll("\x1b[A"),
        .cursor_down => try stdout.writeAll("\x1b[B"),
        .cursor_left => try stdout.writeAll("\x1b[D"),
        .cursor_right => try stdout.writeAll("\x1b[C"),
        _ => if (std.ascii.isPrint(byte)) {
            try stdout.writeByte(byte);
        },
    }
}

pub fn init(allocator: std.mem.Allocator, debug_mode: bool) !Terminal {
    const original_terminal = if (builtin.os.tag == .windows)
        try initWindows()
    else
        try initPosix();

    return Terminal{
        .original = original_terminal,
        .poller = std.io.poll(allocator, PollKinds, .{
            .stdin = std.io.getStdIn(),
        }),
        .debug_input_fifo = if (debug_mode)
            .init(allocator)
        else
            null,
    };
}

fn initWindows() !OriginalTerminal {
    var result: OriginalTerminal = .{
        .mode = .{
            .in = undefined,
            .out = undefined,
        },
    };

    const stdin_handle = try std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE);

    const enable_line_input: DWord = 0x2; // cooked input
    const enable_echo_input: DWord = 0x4; // echo on input
    const enable_virtual_terminal_input: DWord = 0x200; // VT input sequences

    try initWindowsConsoleMode(
        &result.mode.in,
        stdin_handle,
        &.{enable_virtual_terminal_input},
        &.{ enable_line_input, enable_echo_input },
    );

    const stdout_handle = try std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE);

    const enable_processed_output: DWord = 0x1; // required for enable_virtual_terminal_processing
    const enable_virtual_terminal_processing: DWord = 0x4; // enable VT output sequences
    const disable_newline_auto_return: DWord = 0x8; // when enabled, disables automatic \r on \n (i think?)

    try initWindowsConsoleMode(
        &result.mode.out,
        stdout_handle,
        &.{ enable_processed_output, enable_virtual_terminal_processing, disable_newline_auto_return },
        &.{},
    );

    return result;
}

fn initWindowsConsoleMode(
    original_mode: *DWord,
    handle: *anyopaque,
    enable_flags: []const DWord,
    disable_flags: []const DWord,
) !void {
    if (std.os.windows.kernel32.GetConsoleMode(handle, original_mode) == 0) {
        return error.FailedToGetConsoleMode;
    }

    var raw_mode = original_mode.*;

    for (enable_flags) |flag| {
        raw_mode |= flag;
    }

    for (disable_flags) |flag| {
        raw_mode &= ~flag;
    }

    if (std.os.windows.kernel32.SetConsoleMode(handle, raw_mode) == 0) {
        return error.FailedToSetConsoleMode;
    }
}

fn initPosix() !OriginalTerminal {
    const stdin_handle = std.io.getStdIn().handle;
    const original_termios = try std.posix.tcgetattr(stdin_handle);

    var raw_termios = original_termios;

    raw_termios.iflag.INLCR = true;

    raw_termios.oflag.OPOST = true;

    raw_termios.lflag.ECHO = false;
    raw_termios.lflag.ECHONL = false;
    raw_termios.lflag.ICANON = false;
    raw_termios.lflag.ISIG = true;
    raw_termios.lflag.IEXTEN = false;

    raw_termios.cflag.PARENB = false;
    raw_termios.cflag.CSIZE = .CS8;
    raw_termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    raw_termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;

    try std.posix.tcsetattr(stdin_handle, .FLUSH, raw_termios);

    return .{
        .termios = original_termios,
    };
}

pub fn deinit(terminal: *Terminal) void {
    if (terminal.debug_input_fifo) |fifo| {
        fifo.deinit();
    }

    terminal.poller.deinit();

    if (builtin.os.tag == .windows) {
        terminal.deinitWindows();
    } else {
        terminal.deinitPosix();
    }
}

fn deinitWindows(terminal: Terminal) void {
    // TODO: is this function needed?
    const stdin_handle = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch
        std.debug.panic("failed to get stdin handle on deinit", .{});
    const stdout_handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch
        std.debug.panic("failed to get stdin handle on deinit", .{});

    var success = std.os.windows.kernel32.SetConsoleMode(
        stdin_handle,
        terminal.original.mode.in,
    );

    success &= std.os.windows.kernel32.SetConsoleMode(
        stdout_handle,
        terminal.original.mode.out,
    );

    if (success == 0)
        std.debug.panic("Failed to reset terminal settings\n", .{});
}

fn deinitPosix(terminal: Terminal) void {
    const stdin_handle = std.io.getStdIn().handle;
    std.posix.tcsetattr(stdin_handle, .FLUSH, terminal.original.termios) catch
        std.debug.panic("Failed to reset termios\n", .{});
}

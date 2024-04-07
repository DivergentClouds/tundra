const std = @import("std");
const builtin = @import("builtin");

const c =
    if (builtin.target.os.tag == .windows)
    @cImport({
        @cInclude("windows.h");
        @cInclude("conio.h");
    })
else
    undefined;

const reserved_mmio_space = 0x10; // reserved space at the top of memory for mmio
const max_memory = 0x1_0000 - reserved_mmio_space;
const max_storage = 0xff_ffff;

pub fn main() !void {
    var allocator_type =
        comptime if (builtin.mode == .Debug)
        std.heap.GeneralPurposeAllocator(.{
            .never_unmap = true,
            .retain_metadata = true,
        }){}
    else if (builtin.target.os.tag == .windows)
        std.heap.HeapAllocator.init()
    else
        std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = allocator_type.deinit();

    const allocator = allocator_type.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var memory_name: ?[]const u8 = null;
    var storage_names = std.ArrayList([]const u8).init(allocator);
    defer storage_names.deinit();

    var debugger_mode = false;

    const args0 = args.next() orelse
        return error.NoArg0; // skip args[0]
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            if (args.next()) |next_arg| {
                try storage_names.append(next_arg);
            } else {
                printUsage(
                    std.io.getStdErr(),
                    args0,
                    "Expected storage file when none was given",
                ) catch {};
                return error.ExpectedStorageFile;
            }
        } else if (std.mem.eql(u8, arg, "-d")) {
            debugger_mode = true;
        } else {
            if (memory_name == null) {
                memory_name = arg;
            } else {
                printUsage(
                    std.io.getStdErr(),
                    args0,
                    "Can not load more than one memory file",
                ) catch {};
                return error.TooManyMemoryFiles;
            }
        }
    }
    if (memory_name == null) {
        printUsage(
            std.io.getStdErr(),
            args0,
            "Expected memory file when none was given",
        ) catch {};
        return error.NoMemoryFile;
    }

    const memory = try allocator.alloc(u8, max_memory);
    defer allocator.free(memory);

    var memory_file = try std.fs.cwd().openFile(memory_name.?, .{});
    defer memory_file.close();

    const memory_file_size = (try memory_file.metadata()).size();
    if (memory_file_size > max_memory) {
        try std.io.getStdErr().writer().print(
            \\Error: Memory file too large
            \\Max size is 0x{x} bytes
            \\
        , .{max_memory});
        return error.MemoryFileTooLarge;
    }

    _ = try memory_file.readAll(memory);

    var storage_files = std.ArrayList(std.fs.File).init(allocator);
    defer storage_files.deinit();

    defer for (storage_files.items) |file| {
        file.close();
    };

    if (storage_names.items.len > 4) {
        printUsage(
            std.io.getStdErr(),
            args0,
            "Expect at most 4 storage files, when more were given",
        ) catch {};
        return error.TooManyStorageFiles;
    }

    for (storage_names.items) |name| {
        try storage_files.append(try std.fs.cwd().createFile(name, .{
            .truncate = false,
            .read = true,
        }));
    }

    try interpret(
        memory,
        allocator,
        storage_files.items,
        debugger_mode,
    );
}

const Mmio = enum(u16) {
    /// read: reads LSB from input (stdin), clears MSB, blocks
    char_in = 0xfff0,
    /// write: writes LSB to output (stdout)
    char_out,
    /// read/write: stores least significant word of the 24-bit seek address
    seek_lsw,
    /// read/write: stores most significant byte of the 24-bit seek address
    seek_msb,
    /// read/write: stores the chunk size for storage access
    chunk_size,
    /// write: writes a chunk from storage at the seek address to memory at the
    /// given address
    storage_in,
    /// write: writes chunk from memory at the given address at the seek address
    /// in storage
    storage_out,
    /// read: reads the number of attached storage devices
    storage_count,
    /// write: set which storage device to access, 0-indexed
    storage_index,
    /// halts the system
    halt = 0xffff,
    _,
};

const Opcode = enum(u3) {
    op_mov,
    op_sto,
    op_add,
    op_cmp,
    op_shf,
    op_and,
    op_nor,
    op_xor,
};

const Register = enum(u2) {
    a,
    b,
    c,
    pc,
};

const Instruction = struct {
    opcode: Opcode,
    reg_w: Register,
    deref_r: bool,
    reg_r: Register,
};

const MmioState = switch (builtin.target.os.tag) {
    .windows => struct {
        allocator: std.mem.Allocator,
        running: bool,
        seek_address: u24,
        chunk_size: u16,
        storage_files: []std.fs.File,
        storage_index: u16,
        memory: []u8,
        stdin_handle: i64,
    },
    else => struct {
        allocator: std.mem.Allocator,
        running: bool,
        seek_address: u24,
        chunk_size: u16,
        storage_files: []std.fs.File,
        storage_index: u16,
        memory: []u8,
        stdin_handle: i64,
        original_termios: std.posix.termios = undefined,
    },
};

fn mmio(
    address: u16,
    optional_value: ?u16, // null on reads
    state: *MmioState,
) !?u16 {
    const storage_file = if (state.storage_files.len > 0)
        state.storage_files[state.storage_index]
    else
        undefined;

    switch (@as(Mmio, @enumFromInt(address))) {
        .char_in => {
            if (optional_value == null) {
                if (builtin.target.os.tag == .windows) {
                    if (!c._kbhit()) {
                        return 0xffff;
                    }
                    const char = c._getch();

                    if (char == 0 or char == 0xe0) { // function or arrow key
                        _ = c._getch();
                        return 0xffff;
                    } else {
                        return char;
                    }
                } else {
                    var char: u16 = std.io.getStdIn().reader().readByte() catch 0xffff;

                    if (char == 0x1b) { // skip escape sequences
                        while (char != 0xffff) {
                            char = std.io.getStdIn().reader().readByte() catch 0xffff;
                        }
                    }

                    return char;
                }
            }
        },
        .char_out => {
            if (optional_value) |value| {
                try std.io.getStdOut().writer().writeByte(@truncate(value));
            }
        },
        .halt => {
            if (optional_value) |_| {
                state.running = false;
            }
        },
        .seek_lsw => {
            if (optional_value) |value| {
                state.seek_address = (state.seek_address & 0xff0000) | value;
            } else {
                return @truncate(state.seek_address);
            }
        },
        .seek_msb => {
            if (optional_value) |value| {
                state.seek_address =
                    (state.seek_address & 0xffff) | @as(u24, value) << 16;
            } else {
                return @truncate(state.seek_address >> 16);
            }
        },
        .chunk_size => {
            if (optional_value) |value| {
                state.chunk_size = value;
            } else {
                return state.chunk_size;
            }
        },
        .storage_in => {
            if (optional_value) |value| {
                if (state.storage_files.len > 0) {
                    try storage_file.seekTo(state.seek_address);
                    const amount_read = try storage_file.reader().readAll(
                        state.memory[value..@min(
                            state.memory.len,
                            state.chunk_size +| value,
                        )],
                    );

                    if (amount_read < state.chunk_size) {
                        @memset(
                            state.memory[amount_read + value .. @min(
                                state.memory.len,
                                state.chunk_size +| value,
                            )],
                            0,
                        );
                    }
                } else {
                    @memset(
                        state.memory[value..@min(
                            state.memory.len,
                            state.chunk_size +| value,
                        )],
                        0,
                    );
                }
                state.seek_address +%= state.chunk_size;
            }
        },
        .storage_out => {
            if (optional_value) |value| {
                if (state.storage_files.len > 0) {
                    // make sure not to write beyond max storage size
                    const actual_chunk_size: u16 =
                        if (@as(u32, state.seek_address) + state.chunk_size > max_storage)
                        @truncate(max_storage - state.seek_address)
                    else
                        state.chunk_size;

                    try storage_file.seekTo(state.seek_address);
                    try storage_file.writer().writeAll(
                        state.memory[value..@min(
                            state.memory.len,
                            actual_chunk_size +| value,
                        )],
                    );
                    state.seek_address +%= state.chunk_size;
                }
            }
        },
        .storage_count => {
            if (optional_value == null) {
                return @intCast(state.storage_files.len);
            }
        },
        .storage_index => {
            if (optional_value) |value| {
                state.storage_index =
                    if (value <= 4)
                    value
                else
                    undefined;
            }
        },
        _ => return null,
    }

    return null;
}

fn setRegister(
    id: Register,
    value: u16,
    cmp_flag: *bool, // result of op_cmp, true if pc is not writable
    registers: *[4]u16,
) void {
    if (id == .pc) {
        if (cmp_flag.*) {
            cmp_flag.* = false;
            return;
        }
        // stop crash when moving to mmio space
        registers[@intFromEnum(id)] = @min(value, max_memory - 1);
    }
    registers[@intFromEnum(id)] = value;
}

fn getRegister(
    id: Register,
    registers: [4]u16,
) u16 {
    return registers[@intFromEnum(id)];
}

fn parseInstruction(byte: u8) Instruction {
    return Instruction{
        .opcode = @enumFromInt(byte >> 5),
        .reg_w = @enumFromInt(@as(
            u2,
            @truncate(byte >> 3),
        )),
        .deref_r = (1 == @as(
            u1,
            @truncate(byte >> 2),
        )),
        .reg_r = @enumFromInt(@as(
            u2,
            @truncate(byte),
        )),
    };
}

fn getRValue(
    reg_r: Register,
    deref_r: bool,
    memory: []u8,
    registers: *[4]u16,
    state: *MmioState,
) !u16 {
    const pc = @intFromEnum(Register.pc); // for register access
    var r_value = getRegister(reg_r, registers.*);

    if (deref_r) {
        if (r_value < max_memory - 1) {
            r_value = memory[r_value] +
                (@as(u16, memory[r_value + 1]) << 8);
        } else {
            const mmio_optional = try mmio(
                r_value,
                null,
                state,
            );
            if (mmio_optional) |mmio_value| {
                r_value = mmio_value;
            } else {
                return error.InvalidMMIOAccess;
            }
        }
        if (reg_r == .pc) {
            registers[pc] += 2;
        }
    }

    return r_value;
}

fn flushStdin(state: MmioState) !void {
    const stdin = std.io.getStdIn();
    const stdin_handle = stdin.handle;
    if (builtin.target.os.tag == .windows) {
        if (c.FlushConsoleInputBuffer(@intCast(stdin_handle)) == 0) {
            return error.CouldNotFlushInput;
        }
    } else {
        try std.posix.tcsetattr(@intCast(stdin_handle), .FLUSH, state.original_termios);
    }
}

fn interpret(
    memory: []u8,
    allocator: std.mem.Allocator,
    storage: []std.fs.File,
    debugger: bool,
) !void {
    const pc = @intFromEnum(Register.pc); // for register access
    var registers: [4]u16 = .{undefined} ** 4;
    registers[pc] = 0;

    var cmp_flag = false;
    const stdin_handle: i64 = if (builtin.target.os.tag == .windows)
        std.os.windows.STD_INPUT_HANDLE
    else
        std.io.getStdIn().handle;

    var state: MmioState = .{
        .allocator = allocator,
        .running = true,
        .seek_address = 0,
        .chunk_size = 0,
        .storage_files = storage,
        .storage_index = 0,
        .memory = memory,
        .stdin_handle = stdin_handle,
    };

    if (builtin.target.os.tag != .windows)
        state.original_termios = try std.posix.tcgetattr(@intCast(state.stdin_handle));

    // attempt to flush any remaining stdin characters
    defer flushStdin(state) catch {};

    if (builtin.target.os.tag != .windows) {
        var raw = state.original_termios;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;

        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        try std.posix.tcsetattr(@intCast(state.stdin_handle), .FLUSH, raw);
    }

    while (state.running) {
        const instruction = parseInstruction(memory[registers[pc]]);

        registers[pc] +%= 1;
        // entered non-executable mmio area
        if (registers[pc] >= max_memory) {
            return error.EnteredMMIOSpace;
        }

        if (debugger) {
            try print("{x:0>4}: ", .{registers[pc] -% 1});
        }

        const r_value =
            try getRValue(
            instruction.reg_r,
            instruction.deref_r,
            memory,
            &registers,
            &state,
        );

        if (debugger) {
            try print("{s} {s: >2} ({x:0>4}), {s}{s: <2} ({x:0>4})\n", .{
                @tagName(instruction.opcode)[3..],
                @tagName(instruction.reg_w),
                registers[@intFromEnum(instruction.reg_w)],
                if (instruction.deref_r) "*" else "",
                @tagName(instruction.reg_r),
                if (instruction.reg_r == .pc)
                    registers[@intFromEnum(Register.pc)] -% 2
                else
                    registers[@intFromEnum(instruction.reg_r)],
            });
            if (instruction.deref_r) try print(
                "                     [{x:0>4}{s}]\n",
                .{
                    r_value,
                    if (registers[@intFromEnum(instruction.reg_r)] >= max_memory - 1)
                        " (mmio)"
                    else
                        "",
                },
            );
        }

        switch (instruction.opcode) {
            .op_mov => {
                setRegister(
                    instruction.reg_w,
                    r_value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_add => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                const value = w_value +% r_value;

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_sto => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                if (w_value < max_memory) {
                    memory[w_value] = @truncate(r_value);
                    memory[w_value + 1] = @truncate(r_value >> 8);
                } else {
                    _ = try mmio(
                        w_value,
                        r_value,
                        &state,
                    );
                }
            },
            .op_cmp => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                cmp_flag = @as(i16, @bitCast(w_value)) > @as(i16, @bitCast(r_value));
            },
            .op_shf => {
                var w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                const shift_value: u4 = @truncate(r_value);
                const do_left = r_value & 0b1_0000 != 0;
                const do_rotate = r_value & 0b10_0000 != 0;
                const do_sign_extend = r_value & 0b100_0000 != 0;

                // left vs right shift
                if (do_left) {
                    if (do_rotate) {
                        w_value = std.math.rotl(u16, w_value, shift_value);
                    } else {
                        w_value <<= shift_value;
                    }
                } else {
                    if (do_rotate) {
                        w_value = std.math.rotr(u16, w_value, shift_value);
                    } else if (do_sign_extend) {
                        w_value = @bitCast(
                            @divTrunc(@as(i16, @bitCast(w_value)), (@as(i16, 1) << shift_value)),
                        );
                    } else {
                        w_value >>= shift_value;
                    }
                }

                setRegister(
                    instruction.reg_w,
                    w_value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_and => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                const value = r_value & w_value;

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_nor => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                const value = ~(r_value | w_value);

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_xor => {
                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                const value = r_value ^ w_value;

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
        }
    }
}

fn printUsage(
    output: std.fs.File,
    args0: []const u8,
    err_msg: []const u8,
) !void {
    try output.writer().print(
        \\Usage:
        \\{s} <memory_file> [-s storage_file]... [-d]
        \\{s}
        \\
    , .{ args0, err_msg });
}

fn print(comptime format: []const u8, args: anytype) !void {
    const stderr = std.io.getStdErr().writer();

    try stderr.print(format, args);
}

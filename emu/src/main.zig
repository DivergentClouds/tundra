const std = @import("std");
const builtin = @import("builtin");

const c =
    if (builtin.target.os.tag == .windows)
    @cImport({
        @cInclude("windows.h");
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

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3 or args.len > 4) {
        try std.io.getStdErr().writer().print(
            \\Usage:
            \\{s} <memory file> <storage file> [memdump file]
            \\
        , .{args[0]});
        return error.BadArgCount;
    }

    var memory = try allocator.alloc(u8, max_memory);
    defer allocator.free(memory);

    var memory_file = try std.fs.cwd().openFile(args[1], .{});
    defer memory_file.close();

    const memory_file_size = (try memory_file.metadata()).size();
    if (memory_file_size > max_memory) {
        try std.io.getStdErr().writer().print(
            \\Error: Memory file too large
            \\ Max size is 0x{x} bytes
            \\
        , .{max_memory});
        return error.MemoryFileTooLarge;
    }

    _ = try memory_file.readAll(memory);

    var storage_file = try std.fs.cwd().createFile(args[2], .{
        .truncate = false,
        .read = true,
    });
    defer storage_file.close();

    try interpret(
        memory,
        allocator,
        storage_file,
    );

    if (args.len == 4) {
        var memdump_file = try std.fs.cwd().createFile(args[3], .{});
        defer memdump_file.close();

        try memdump_file.writer().writeAll(memory);
    }
}

const Opcodes = enum(u3) {
    op_mov,
    op_add,
    op_neg,
    op_sto,
    op_cmp,
    op_shf,
    op_and,
    op_nor,
};

const Registers = enum(u2) {
    a,
    b,
    c,
    pc,
};

const Instruction = struct {
    opcode: Opcodes,
    reg_w: Registers,
    deref_r: bool,
    reg_r: Registers,
};

const MemoryMap = enum(u16) {
    // read: reads 1 if input has a byte available, 0 otherwise
    char_in_ready = max_memory,
    // read: reads LSB from input (stdin), clears MSB, blocks
    char_in,
    // write: writes LSB to output (stdout)
    char_out,
    // read/write: stores least significant word of the 24-bit seek address
    seek_lsw,
    // read/write: stores most significant byte of the 24-bit seek address
    seek_msb,
    // read/write: stores the chunk size for storage access
    chunk_size,
    // write: writes a chunk from storage at the seek address to memory at the
    // given address
    storage_in,
    // write: writes chunk from memory at the given address at the seek address
    // in storage
    storage_out,
    // halts the system
    halt = 0xffff,
    _,
};

const MmioState = struct {
    allocator: std.mem.Allocator,
    running: bool,
    seek_address: u24,
    chunk_size: u16,
    storage_file: std.fs.File,
    memory: []u8,
};

fn mmio(
    address: u16,
    optional_value: ?u16, // null on reads
    state: *MmioState,
) !?u16 {
    switch (@as(MemoryMap, @enumFromInt(address))) {
        .char_in_ready => {
            if (builtin.target.os.tag == .windows) {
                const stdin_handle = std.io.getStdIn().handle;

                var event_count: u32 = 0;

                if (c.GetNumberOfConsoleInputEvents(stdin_handle, &event_count) == 0) {
                    return error.WinCouldNotCountInputEvents;
                }

                if (event_count == 0) {
                    return 0;
                } else {
                    var peek_buffer = try state.allocator.alloc(
                        c.INPUT_RECORD,
                        event_count,
                    );
                    defer state.allocator.free(peek_buffer);

                    if (c.PeekConsoleInputA(
                        stdin_handle,
                        peek_buffer.ptr,
                        @intCast(peek_buffer.len),
                        &event_count,
                    ) == 0) {
                        return error.WinCouldNotPeekInput;
                    }

                    for (peek_buffer) |input_record| {
                        const KEY_EVENT = 1;
                        if (input_record.EventType != KEY_EVENT) continue;

                        const char = input_record.Event.KeyEvent.uChar.AsciiChar;
                        if (char == '\r') return 1;
                    }
                    return 0;
                }
            } else {
                var pfd = [1]std.os.pollfd{
                    .{
                        .fd = std.os.STDIN_FILENO,
                        .events = std.os.POLL.IN,
                        .revents = undefined,
                    },
                };

                // only error that is possible here is running out of mem
                _ = std.os.poll(&pfd, 0) catch {};

                if ((pfd[0].revents & std.os.POLL.IN) == 0) {
                    return 0;
                } else {
                    return 1;
                }
            }
        },
        .char_in => {
            if (optional_value == null) {
                return std.io.getStdIn().reader().readByte() catch 0;
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
                try state.storage_file.seekTo(state.seek_address);
                const amount_read = try state.storage_file.reader().readAll(
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
            }
        },
        .storage_out => {
            if (optional_value) |value| {
                // make sure not to write beyond max storage size
                const actual_chunk_size: u16 =
                    if (@as(u32, state.seek_address) + state.chunk_size > max_storage)
                    @truncate(max_storage - state.seek_address)
                else
                    state.chunk_size;

                try state.storage_file.seekTo(state.seek_address);
                try state.storage_file.writer().writeAll(
                    state.memory[value..@min(
                        state.memory.len,
                        actual_chunk_size +| value,
                    )],
                );
            }
        },
        _ => return null,
    }

    return null;
}

fn setRegister(
    id: Registers,
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
        registers[@intFromEnum(id)] = @max(value, max_memory - 1);
    }
    registers[@intFromEnum(id)] = value;
}

fn getRegister(
    id: Registers,
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
    reg_r: Registers,
    deref_r: bool,
    memory: []u8,
    registers: *[4]u16,
    state: *MmioState,
) !u16 {
    const pc = @intFromEnum(Registers.pc); // for register access
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

fn interpret(
    memory: []u8,
    allocator: std.mem.Allocator,
    storage: std.fs.File,
) !void {
    const pc = @intFromEnum(Registers.pc); // for register access
    var registers: [4]u16 = .{undefined} ** 4;
    registers[pc] = 0;

    var cmp_flag = false;

    var state: MmioState = .{
        .allocator = allocator,
        .running = true,
        .seek_address = 0,
        .chunk_size = 0,
        .storage_file = storage,
        .memory = memory,
    };

    while (state.running) {
        const instruction = parseInstruction(memory[registers[pc]]);

        registers[pc] +%= 1;
        // entered non-executable mmio area
        if (registers[pc] >= max_memory) {
            return error.EnteredMMIOSpace;
        }

        switch (instruction.opcode) {
            .op_mov => {
                const value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_add => {
                const r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                var w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                w_value = @bitCast(
                    @as(i16, @bitCast(w_value)) +
                        @as(i16, @bitCast(r_value)),
                );

                setRegister(
                    instruction.reg_w,
                    w_value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_neg => {
                var value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                value = @bitCast(0 - @as(i16, @bitCast(value)));

                setRegister(
                    instruction.reg_w,
                    value,
                    &cmp_flag,
                    &registers,
                );
            },
            .op_sto => {
                const r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

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
                const r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                cmp_flag = @as(i16, @bitCast(w_value)) > @as(i16, @bitCast(r_value));
            },
            .op_shf => {
                const r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                var w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                if (@as(i16, @bitCast(r_value)) < 0) {
                    const shift_amount = std.math.absCast(@as(i16, @bitCast(r_value)));

                    if (shift_amount > 15) {
                        w_value = 0; // all bits shifted out
                    } else {
                        w_value <<= @truncate(shift_amount);
                    }
                } else {
                    if (r_value > 15) {
                        w_value = 0; // all bits shifted out
                    } else {
                        w_value >>= @truncate(r_value);
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
                var r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                var w_value = getRegister(
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
                var r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
                    &state,
                );

                var w_value = getRegister(
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
        }
    }
}

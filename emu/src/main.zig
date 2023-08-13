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
const max_memory = 0x10000 - reserved_mmio_space;

const PossibleAllocators = enum {
    debug_general_purpose, // Debug Mode, GPA with extra config settings
    c, // for if linking libc
    heap, // Windows
    general_purpose, // else
};

const AllocatorType = union(PossibleAllocators) {
    debug_general_purpose: std.heap.GeneralPurposeAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
    }),
    c: void,
    heap: if (builtin.target.os.tag == .windows) std.heap.HeapAllocator else void,
    general_purpose: std.heap.GeneralPurposeAllocator(.{}),
};

pub fn main() !void {
    const allocator_kind: PossibleAllocators =
        comptime if (builtin.mode == .Debug)
        .debug_general_purpose
    else if (builtin.link_libc)
        .c
    else if (builtin.target.os.tag == .windows)
        .heap
    else
        .general_purpose;

    var allocator_type = switch (allocator_kind) {
        .debug_general_purpose => std.heap.GeneralPurposeAllocator(.{
            .never_unmap = true,
            .retain_metadata = true,
        }){},
        .heap => std.heap.HeapAllocator.init(),
        .c => {},
        .general_purpose => std.heap.GeneralPurposeAllocator(.{}){},
    };

    defer if (allocator_kind != .c) {
        _ = allocator_type.deinit();
    };

    const allocator = if (allocator_kind == .c)
        std.heap.c_allocator
    else
        allocator_type.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2 or args.len > 3) {
        try std.io.getStdErr().writer().print(
            \\Usage:
            \\{s} <memory file> [memdump file]
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

    try interpret(memory);

    if (args.len == 3) {
        var memdump_file = try std.fs.cwd().createFile(args[2], .{});
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
    // does nothing on write, reads 1 if input has a byte available, 0 otherwise
    char_in_ready = max_memory,
    // does nothing on write, reads LSB from input (stdin), clears MSB, blocks
    char_in,
    // does nothing on read, writes LSB to output (stdout)
    char_out,
    // halts the system
    halt = 0xffff,
    _,
};

fn mmio(
    address: u16,
    optional_value: ?u16, // null on reads
    running: ?*bool, // null on reads
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
                    var peek_buffer: [4096]c.INPUT_RECORD = undefined;

                    if (c.PeekConsoleInputA(stdin_handle, &peek_buffer, peek_buffer.len, &event_count) == 0) {
                        return error.WinCouldNotPeekInput;
                    }

                    for (peek_buffer, 0..) |input_record, i| {
                        if (i >= event_count) return 0;

                        if (input_record.EventType != 1) continue;

                        const char = input_record.Event.KeyEvent.uChar.AsciiChar;
                        if (char == '\r') return 1;
                    }
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
                return try std.io.getStdIn().reader().readByte();
            }
        },
        .char_out => {
            if (optional_value) |value| {
                try std.io.getStdOut().writer().writeByte(@truncate(value));
            }
        },
        .halt => {
            if (optional_value) |_| {
                running.?.* = false;
            }
        },
        _ => {},
    }

    return null;
}

fn setRegister(
    id: Registers,
    value: u16,
    cmp_flag: *bool, // result of op_cmp, true if pc is not writable
    registers: *[4]u16,
) void {
    if (id == .pc and cmp_flag.*) {
        cmp_flag.* = false;
        return;
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
) !u16 {
    const pc = @intFromEnum(Registers.pc); // for register access
    var r_value = getRegister(reg_r, registers.*);

    if (deref_r) {
        if (r_value < max_memory) {
            r_value = memory[r_value] + (@as(u16, memory[r_value + 1]) << 8);
        } else {
            const mmio_optional = try mmio(r_value, null, null);
            if (mmio_optional) |mmio_value| {
                r_value = mmio_value;
            }
        }
        if (reg_r == .pc) {
            registers[pc] += 2;
        }
    }

    return r_value;
}

fn interpret(memory: []u8) !void {
    const pc = @intFromEnum(Registers.pc); // for register access
    var registers: [4]u16 = .{undefined} ** 4;
    registers[pc] = 0;

    var cmp_flag = false;

    var running = true;
    while (running) {
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
                );

                const w_value = getRegister(
                    instruction.reg_w,
                    registers,
                );

                if (w_value < max_memory) {
                    memory[w_value] = @truncate(r_value);
                    memory[w_value + 1] = @truncate(r_value >> 8);
                } else {
                    _ = try mmio(w_value, r_value, &running);
                }
            },
            .op_cmp => {
                const r_value = try getRValue(
                    instruction.reg_r,
                    instruction.deref_r,
                    memory,
                    &registers,
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

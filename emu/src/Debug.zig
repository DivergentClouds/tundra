const std = @import("std");
const Core = @import("root").Core;
const Debug = @This();

pub const Command = @import("debug/command.zig").Command;
pub const CommandKind = @import("debug/command.zig").CommandKind;
pub const Breakpoint = @import("debug/Breakpoint.zig");

const Cpu = @import("core/Cpu.zig");
const Terminal = @import("core/Terminal.zig");

debug_print: bool,
breakpoint_list: std.AutoHashMap(u16, Breakpoint),
core: *Core,
cleanup: *bool,

pub fn init(core: *Core, cleanup: *bool, allocator: std.mem.Allocator) Debug {
    return .{
        .debug_print = false,
        .breakpoint_list = .init(allocator),
        .core = core,
        .cleanup = cleanup,
    };
}

pub fn deinit(debug: *Debug) void {
    debug.breakpoint_list.deinit();
}

pub fn setBreakpoint(debug: *Debug, address: u16, breakpoint: Breakpoint) !void {
    try debug.breakpoint_list.put(address, breakpoint);
}

pub fn checkAddress(debug: *const Debug, address: u16) ?Breakpoint {
    const breakpoint: Breakpoint = debug.breakpoint_list.get(address) orelse
        return null;

    if (breakpoint.read == false and
        breakpoint.write == false and
        breakpoint.execute == false)
    {
        return null;
    }

    return breakpoint;
}

pub fn execute(debug: *Debug, command: Command) !void {
    switch (command) {
        .run => try debug.step(null),
        .step => |count| try debug.step(count),
        // debug_input_fifo is only null when not in debug mode
        .input => |string| try debug.core.terminal.debug_input_fifo.?.write(string),
        .jump => |address| debug.core.cpu.registers.pc = address,
        .set_reg => |fields| {
            Cpu.Registers.setNoCheck(
                fields.register,
                fields.value,
                &debug.core.cpu,
            );
        },
        .get_reg => |register| try debug.printReg(register),
        .write_mem => |fields| {
            const stderr = std.io.getStdErr().writer();

            // each item is a 16-bit word
            const overflow, _ = @addWithOverflow(fields.starting_address, fields.values.len * 2);
            if (overflow == 1) {
                try stderr.print("Attempt to write beyond addressing space\n", .{});
            }

            for (fields.values, 0..) |value, index| {
                debug.core.memory.writeWord(
                    @intCast(fields.starting_address + index),
                    value,
                ) catch |err| switch (err) {
                    error.InvalidMmioWrite => {
                        try stderr.print(
                            "Invalid MMIO write at address {x:0>4}\n",
                            .{fields.starting_address + index},
                        );
                    },
                    else => return err,
                };
            }
        },
        .read_mem => |fields| {
            const stderr = std.io.getStdErr().writer();

            var address: u16 = fields.starting_address;
            var overflow: u1 = 0;
            const ending_address = fields.ending_address orelse fields.starting_address;

            // `Command.parse` will fail if ending_address is less than starting_address
            while (address <= ending_address and overflow == 0) : ({
                address, overflow = @addWithOverflow(address, 2);
            }) {
                const value = debug.core.memory.readWord(address) catch |err| switch (err) {
                    error.InvalidMmioRead => {
                        try stderr.print("Invalid MMIO read at address {x:0>4}\n", .{address});
                        break;
                    },
                    else => return err,
                };
                try stderr.print("{x:0>4}", .{value});
            }
        },
        .breakpoint => |breakpoint| try debug.setBreakpoint(breakpoint.address, breakpoint.kinds),
        .help => |command_kind| try printHelp(command_kind),
        .log => |log| debug.debug_print = log,
        .quit => debug.core.cpu.running = false,
        .fail => |reason| try Command.printFailed(reason),
    }
}

fn printHelp(kind: ?CommandKind) !void {
    _ = kind;
}

fn step(debug: *Debug, optional_count: ?usize) !void {
    // we have already set terminal.original, so we can ignore the result
    _ = try Terminal.uncook();

    if (optional_count) |count| {
        for (0..count) |_| {
            if (debug.core.cpu.running and !debug.cleanup.*) {
                // TODO:
            }
        }
    }
}

fn printReg(debug: Debug, register: Cpu.RegisterKind) !void {
    const stderr = std.io.getStdErr().writer();

    switch (register) {
        .a => try stderr.print("{a:0>4}\n", .{debug.core.cpu.registers}),
        .b => try stderr.print("{b:0>4}\n", .{debug.core.cpu.registers}),
        .c => try stderr.print("{c:0>4}\n", .{debug.core.cpu.registers}),
        .pc => try stderr.print("{pc:0>4}\n", .{debug.core.cpu.registers}),
    }
}

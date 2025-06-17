const std = @import("std");
const builtin = @import("builtin");

const Cpu = @import("core/Cpu.zig");
const Io = @import("core/Io.zig");
const Memory = @import("core/Memory.zig");
const Storage = @import("core/Storage.zig");
const Terminal = @import("core/Terminal.zig");
const DateTime = @import("core/DateTime.zig");

const Debug = @import("Debug.zig");

/// set by signal handler when SIGINT is received
var cleanup = false;

pub const Core = struct {
    cpu: Cpu,
    io: Io,
    memory: Memory,
    storage: Storage,
    terminal: Terminal,
    datetime: DateTime,
    timestamp: i128,

    allocator: std.mem.Allocator,

    fn init(
        allocator: std.mem.Allocator,
        storage_files: []const std.fs.File,
        debug_mode: bool,
    ) !*Core {
        var core = try allocator.create(Core);

        core.cpu = .init;

        core.storage = try .init(allocator, storage_files);
        errdefer core.storage.deinit();

        core.terminal = try .init(allocator, debug_mode);
        errdefer core.terminal.deinit();

        core.datetime = try .init();

        core.io = .{
            .cpu = &core.cpu,
            .memory = &core.memory,
            .storage = &core.storage,
            .terminal = &core.terminal,
            .datetime = &core.datetime,
        };

        core.memory = try .init(allocator, core.io);

        core.allocator = allocator;
        core.timestamp = std.time.nanoTimestamp();

        return core;
    }

    fn deinit(core: *Core) void {
        core.memory.deinit();
        core.storage.deinit();
        core.terminal.deinit();

        core.allocator.destroy(core);
    }

    /// does 1 instruction
    pub fn step(core: *Core, debug_print: bool) !void {
        if (core.cpu.instruction_state != .fetch)
            return error.InvalidStartOfStep;

        const pre_fetch_pc = core.cpu.registers.pc;

        if (core.cpu.instruction_state == .fetch) {
            const clock_increment = try core.cpu.doTick(&core.memory, &core.terminal);
            core.cpu.clock_counter +%= clock_increment;
            Cpu.clockDelay(&core.timestamp, clock_increment);
        } else {
            return error.UnexpectedFetch;
        }

        while (core.cpu.instruction_state != .fetch and
            core.cpu.running)
        {
            if (debug_print) {
                const stderr = std.io.getStdErr().writer();

                switch (core.cpu.instruction_state) {
                    .interrupt => |interrupt_kind| try stderr.print(
                        "interrupt: {}\r\n", // need to \r due to termios
                        .{interrupt_kind},
                    ),
                    .read_memory => {},
                    .execute => |instruction_with_data| try stderr.print(
                        "{x:0>4}: {}\r\n",
                        .{
                            pre_fetch_pc,
                            instruction_with_data,
                        },
                    ),
                    .fetch => {},
                }
            }
            const clock_increment = try core.cpu.doTick(&core.memory, &core.terminal);
            core.cpu.clock_counter +%= clock_increment;
            Cpu.clockDelay(&core.timestamp, clock_increment);
        }
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var debugging = false;

    var storage_list: std.ArrayListUnmanaged(std.fs.File) = try .initCapacity(allocator, 4);
    defer {
        for (storage_list.items) |file|
            file.close();

        storage_list.deinit(allocator);
    }

    var optional_rom_file: ?std.fs.File = null;
    defer {
        if (optional_rom_file) |file|
            file.close();
    }

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    std.debug.assert(args.skip());
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-s")) {
            // storage
            const next_arg = args.next() orelse
                return error.NoStorageFileGiven;

            if (storage_list.items.len < 4) {
                storage_list.appendAssumeCapacity(
                    try std.fs.cwd().openFile(next_arg, .{}),
                );
            } else return error.TooManyStorageFiles;
        } else if (std.mem.eql(u8, arg, "-d")) {
            debugging = true;
        } else {
            if (optional_rom_file == null) {
                optional_rom_file = try std.fs.cwd().openFile(arg, .{});
            } else {
                return error.MultipleRomFilesSpecified;
            }
        }
    }

    if (optional_rom_file) |rom_file| {
        const rom = rom_file.readToEndAlloc(
            allocator,
            Memory.region_size,
        ) catch |err| switch (err) {
            error.FileTooBig => return error.RomTooBig,
            else => return err,
        };
        defer allocator.free(rom);

        const storage_files = try storage_list.toOwnedSlice(allocator);
        defer {
            for (storage_files) |file| {
                file.close();
                allocator.free(storage_files);
            }
        }

        try interpret(rom, allocator, storage_files, debugging);
    } else {
        return error.NoRomSpecified;
    }
}

fn interpret(
    rom: []const u8,
    allocator: std.mem.Allocator,
    storage: []const std.fs.File,
    debugging: bool,
) !void {
    var core: *Core = try .init(allocator, storage, debugging);
    defer core.deinit();

    if (builtin.os.tag != .windows) {
        std.posix.sigaction(
            std.posix.SIG.INT,
            &.{
                .handler = .{ .handler = &signalHandler },
                .mask = @splat(0),
                .flags = 0,
            },
            null,
        );
    }

    try core.memory.writeRom(rom);

    // fine to init when not debugging, as this only happens once and the performance hit is minimal
    var debug: Debug = .init(core, &cleanup, allocator);
    defer debug.deinit();

    while (core.cpu.running and !cleanup) {
        if (debugging) {
            if (true)
                return error.DebuggerNotImplimented;
            // uncooked again in Debug.step
            core.terminal.cook();

            // TODO: debugging enviornment

            const command: Debug.Command = try .parse(allocator);
            defer command.deinit(allocator);

            try debug.execute(command);
        } else {
            try core.step(false);
        }
    }
}

fn signalHandler(signum: i32) callconv(.C) void {
    switch (signum) {
        std.posix.SIG.INT => cleanup = true,
        else => {},
    }
}

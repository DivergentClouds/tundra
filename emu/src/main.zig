const std = @import("std");

const Cpu = @import("core/Cpu.zig");
const Io = @import("core/Io.zig");
const Memory = @import("core/Memory.zig");
const Storage = @import("core/Storage.zig");
const Terminal = @import("core/Terminal.zig");

const Core = struct {
    cpu: Cpu,
    io: Io,
    memory: Memory,
    storage: Storage,
    terminal: Terminal,

    allocator: std.mem.Allocator,

    fn init(
        allocator: std.mem.Allocator,
        storage_files: []const std.fs.File,
        debugging: bool,
    ) !*Core {
        var core = try allocator.create(Core);

        core.cpu = .init;

        core.storage = try .init(allocator, storage_files);
        errdefer core.storage.deinit();

        core.terminal = try .init(allocator, debugging);
        errdefer core.terminal.deinit();

        core.io = .{
            .cpu = &core.cpu,
            .memory = &core.memory,
            .storage = &core.storage,
            .terminal = &core.terminal,
        };

        core.memory = try .init(allocator, core.io);

        core.allocator = allocator;

        return core;
    }

    fn deinit(core: *Core) void {
        core.memory.deinit();
        core.storage.deinit();
        core.terminal.deinit();

        core.allocator.destroy(core);
    }

    /// does 1 instruction
    fn step(core: *Core, debug_print: bool) !void {
        if (core.cpu.instruction_state != .fetch)
            return error.InvalidStartOfStep;

        const pre_fetch_pc = core.cpu.registers.pc;
        // fetch
        core.cpu.clock_counter +%= try core.cpu.doTick(&core.memory, &core.terminal);

        while (core.cpu.instruction_state != .fetch and
            core.cpu.running)
        {
            core.cpu.clock_counter +%= try core.cpu.doTick(&core.memory, &core.terminal);

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
    }
}

fn interpret(rom: []const u8, allocator: std.mem.Allocator, storage: []const std.fs.File, debugging: bool) !void {
    var core: *Core = try .init(allocator, storage, debugging);
    defer core.deinit();

    // TODO: handle ctrl-c to reset terminal on early exit

    try core.memory.writeRom(rom);

    if (debugging) {

        // TODO:
    } else {
        while (core.cpu.running) {
            try core.step(debugging); // more readable than just passing `false`
        }
    }
}

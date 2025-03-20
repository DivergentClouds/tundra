const std = @import("std");
const Terminal = @import("core/Terminal.zig");
const Cpu = @import("core/Cpu.zig");

pub const BreakpointKind = enum {
    read,
    write,
    execute,
};

pub const FailReason = enum {
    too_many_args,
    too_few_args,
    invalid_arg,
    unknown_command,
    empty_command,
};

pub const CommandKind = enum {
    run,
    step,
    input,
    jump,
    set,
    get,
    write,
    read,
    breakpoint,
    help,
    echo,
    quit,
    fail,

    fn fromString(string: []const u8) CommandKind {
        if (std.mem.eql(u8, string, "run") or
            std.mem.eql(u8, string, "r"))
            return .run
        else if (std.mem.eql(u8, string, "step") or
            std.mem.eql(u8, string, "st"))
            return .step
        else if (std.mem.eql(u8, string, "input") or
            std.mem.eql(u8, string, "i"))
            return .input
        else if (std.mem.eql(u8, string, "jump") or
            std.mem.eql(u8, string, "j"))
            return .jump
        else if (std.mem.eql(u8, string, "set") or
            std.mem.eql(u8, string, "s"))
            return .set
        else if (std.mem.eql(u8, string, "get") or
            std.mem.eql(u8, string, "g"))
            return .get
        else if (std.mem.eql(u8, string, "write") or
            std.mem.eql(u8, string, "w"))
            return .write
        else if (std.mem.eql(u8, string, "read") or
            std.mem.eql(u8, string, "r"))
            return .read
        else if (std.mem.eql(u8, string, "breakpoint") or
            std.mem.eql(u8, string, "bp"))
            return .breakpoint
        else if (std.mem.eql(u8, string, "help") or
            std.mem.eql(u8, string, "h"))
            return .help
        else if (std.mem.eql(u8, string, "quit") or
            std.mem.eql(u8, string, "q"))
            return .quit
        else
            return .fail;
    }
};

pub const Command = union(CommandKind) {
    run,
    step: ?usize,
    input: []const u8,
    jump: u16, // shorthand for `set pc`
    set: struct {
        register: Cpu.RegisterKind,
        value: u16,
    },
    get: Cpu.RegisterKind,
    write: struct {
        starting_address: u16,
        values: []const u16,
    },
    read: struct {
        starting_address: u16,
        ending_address: u16,
    },
    breakpoint: struct {
        kind: BreakpointKind,
        address: u16,
    },
    help: ?CommandKind,
    echo: bool, // prints instructions as they are executed
    quit,
    fail: FailReason,

    /// any returned strings are owned by the caller
    pub fn getCommand(terminal: *Terminal, allocator: std.mem.Allocator) !Command {
        terminal.deinit();
        defer terminal.* = Terminal.init(allocator, true) catch |err|
            std.debug.panic("Could not reintialize terminal: {s}\n", .{@errorName(err)});

        const stdin = std.io.getStdIn().reader();

        var line_list: std.ArrayListUnmanaged(u8) = try .initCapacity(allocator, 128);
        defer line_list.deinit(allocator);

        try stdin.streamUntilDelimiter(line_list.writer(allocator), '\n', null);

        var tokens = std.mem.tokenizeScalar(u8, line_list.items, ' ');

        const command_string = tokens.next() orelse
            return .{ .fail = .empty_command }; // empty line is ok to fail silently

        const command_kind: CommandKind = .fromString(command_string);

        switch (command_kind) {
            .run => {
                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                return .run;
            },
            .step => {
                const count_string = tokens.next() orelse
                    return .{ .step = null };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const step_count = std.fmt.parseInt(usize, count_string, 0) catch
                    return .{ .fail = .invalid_arg };

                return .{ .step = step_count };
            },
            .input => {
                const input_string = tokens.rest();

                if (input_string.len == 0)
                    return .{ .fail = .too_few_args };

                return .{ .input = try allocator.dupe(u8, input_string) };
            },
            .jump => {
                const address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const address = std.fmt.parseInt(u16, address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                return .{ .jump = address };
            },
            .set => {
                const register_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const value_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const register = std.meta.stringToEnum(Cpu.RegisterKind, register_string) orelse
                    return .{ .fail = .invalid_arg };

                const value = std.fmt.parseInt(u16, value_string, 0) catch
                    return .{ .fail = .invalid_arg };

                return .{ .set = .{ .register = register, .value = value } };
            },
            .get => {
                const register_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const register = std.meta.stringToEnum(Cpu.RegisterKind, register_string) orelse
                    return .{ .fail = .invalid_arg };

                return .{ .get = register };
            },
            .write => {
                const starting_address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const starting_address = std.fmt.parseInt(u16, starting_address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                var values_list: std.ArrayListUnmanaged(u16) = try .initCapacity(allocator, 32);
                defer values_list.deinit(allocator);

                while (tokens.next()) |value_string| {
                    try values_list.append(allocator, std.fmt.parseInt(u16, value_string, 0) catch
                        return .{ .fail = .invalid_arg });
                }

                return .{
                    .write = .{
                        .starting_address = starting_address,
                        .values = try values_list.toOwnedSlice(allocator),
                    },
                };
            },
            .read => {
                const starting_address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const ending_address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const starting_address = std.fmt.parseInt(u16, starting_address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                const ending_address = std.fmt.parseInt(u16, ending_address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                return .{
                    .read = .{
                        .starting_address = starting_address,
                        .ending_address = ending_address,
                    },
                };
            },
            .breakpoint => {
                const breakpoint_kind_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const breakpoint_kind = std.meta.stringToEnum(BreakpointKind, breakpoint_kind_string) orelse
                    return .{ .fail = .invalid_arg };

                const address = std.fmt.parseInt(u16, address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                return .{
                    .breakpoint = .{
                        .kind = breakpoint_kind,
                        .address = address,
                    },
                };
            },
            .help => {
                const help_kind_string = tokens.next() orelse
                    return .{ .help = null };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const help_kind = std.meta.stringToEnum(CommandKind, help_kind_string) orelse
                    return .{ .fail = .invalid_arg };

                return .{ .help = help_kind };
            },
            .echo => {
                const echo_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                if (std.mem.eql(u8, echo_string, "true")) {
                    return .{ .echo = true };
                } else if (std.mem.eql(u8, echo_string, "false")) {
                    return .{ .echo = false };
                } else {
                    return .{ .fail = .invalid_arg };
                }
            },
            .quit => {
                return .quit;
            },
            .fail => {
                return .{ .fail = .unknown_command };
            },
        }
    }

    fn printFailed(
        reason: FailReason,
    ) !void {
        const stderr = std.io.getStdErr().writer();

        try stderr.print("{s}", .{
            switch (reason) {
                .too_many_args => "Too many arguments\n",
                .too_few_args => "Too few arguments\n",
                .invalid_arg => "Invalid argument\n",
                .unknown_command => "Unknown command\n",
                .empty_command => "",
            },
        });
    }
};

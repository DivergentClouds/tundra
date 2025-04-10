const std = @import("std");
const Terminal = @import("../core/Terminal.zig");
const Cpu = @import("../core/Cpu.zig");
const Breakpoint = @import("Breakpoint.zig");
const Debug = @import("../Debug.zig");

pub const CommandKind = enum {
    run,
    step,
    input,
    jump,
    set_reg,
    get_reg,
    write_mem,
    read_mem,
    breakpoint,
    help,
    log,
    quit,
    fail,

    fn fromString(string: []const u8) CommandKind {
        if (std.mem.eql(u8, string, "run"))
            return .run
        else if (std.mem.eql(u8, string, "step") or
            std.mem.eql(u8, string, "s"))
            return .step
        else if (std.mem.eql(u8, string, "input") or
            std.mem.eql(u8, string, "i"))
            return .input
        else if (std.mem.eql(u8, string, "jump") or
            std.mem.eql(u8, string, "j"))
            return .jump
        else if (std.mem.eql(u8, string, "set"))
            return .set_reg
        else if (std.mem.eql(u8, string, "get"))
            return .get_reg
        else if (std.mem.eql(u8, string, "write") or
            std.mem.eql(u8, string, "w"))
            return .write_mem
        else if (std.mem.eql(u8, string, "read") or
            std.mem.eql(u8, string, "r"))
            return .read_mem
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
    step: usize,
    input: []const u8,
    jump: u16, // shorthand for `set_reg pc`
    set_reg: struct {
        register: Cpu.RegisterKind,
        value: u16,
    },
    get_reg: Cpu.RegisterKind,
    write_mem: struct {
        starting_address: u16,
        values: []const u16,
    },
    read_mem: struct {
        starting_address: u16,
        ending_address: ?u16,
    },
    breakpoint: struct {
        address: u16,
        kinds: Breakpoint,
    },
    help: ?CommandKind,
    log: bool, // prints instructions as they are executed
    quit,
    fail: FailReason,

    pub const FailReason = enum {
        too_many_args,
        too_few_args,
        invalid_arg,
        unknown_command,
        empty_command,
        invalid_breakpoint_length,
        invalid_breakpoint_kind,
        duplicate_breakpoint_kind,
        invalid_input_sequence,
        unfinished_input_sequence,
        invalid_address_order,
    };

    pub fn deinit(
        command: Command,
        allocator: std.mem.Allocator,
    ) void {
        switch (command) {
            .input => |input| allocator.free(input),
            .write_mem => |write| allocator.free(write.values),
            else => {},
        }
    }

    /// gets and parses a command
    /// any returned strings are owned by the caller
    pub fn parse(allocator: std.mem.Allocator) !Command {
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
                    return .{ .step = 1 };

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

                const parsed_input = parseInput(input_string, allocator) catch |err| switch (err) {
                    InputParseError.InvalidSequence => return .{ .fail = .invalid_input_sequence },
                    InputParseError.UnfinishedSequence => return .{ .fail = .unfinished_input_sequence },
                    else => return err,
                };
                return .{ .input = parsed_input };
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
            .set_reg => {
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

                return .{ .set_reg = .{ .register = register, .value = value } };
            },
            .get_reg => {
                const register_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const register = std.meta.stringToEnum(Cpu.RegisterKind, register_string) orelse
                    return .{ .fail = .invalid_arg };

                return .{ .get_reg = register };
            },
            .write_mem => {
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
                    .write_mem = .{
                        .starting_address = starting_address,
                        .values = try values_list.toOwnedSlice(allocator),
                    },
                };
            },
            .read_mem => {
                const starting_address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const ending_address_string: ?[]const u8 = tokens.next() orelse
                    null;

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const starting_address = std.fmt.parseInt(u16, starting_address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                if (ending_address_string == null) {
                    return .{ .read_mem = .{
                        .starting_address = starting_address,
                        .ending_address = null,
                    } };
                }

                const ending_address = std.fmt.parseInt(u16, ending_address_string.?, 0) catch
                    return .{ .fail = .invalid_arg };

                if (ending_address < starting_address)
                    return .{ .fail = .invalid_address_order };

                return .{
                    .read_mem = .{
                        .starting_address = starting_address,
                        .ending_address = ending_address,
                    },
                };
            },
            .breakpoint => {
                const address_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                const breakpoint_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                const address = std.fmt.parseInt(u16, address_string, 0) catch
                    return .{ .fail = .invalid_arg };

                // can't use decl literal with catch
                const breakpoint = Breakpoint.parse(breakpoint_string) catch |err| switch (err) {
                    Breakpoint.Error.InvalidBreakpointLength => return .{ .fail = .invalid_breakpoint_length },
                    Breakpoint.Error.InvalidBreakpointKind => return .{ .fail = .invalid_breakpoint_kind },
                    Breakpoint.Error.DuplicateBreakpointKind => return .{ .fail = .duplicate_breakpoint_kind },
                };

                return .{
                    .breakpoint = .{
                        .kinds = breakpoint,
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
            .log => {
                const boolean_string = tokens.next() orelse
                    return .{ .fail = .too_few_args };

                if (tokens.next() != null)
                    return .{ .fail = .too_many_args };

                if (std.mem.eql(u8, boolean_string, "true")) {
                    return .{ .log = true };
                } else if (std.mem.eql(u8, boolean_string, "false")) {
                    return .{ .log = false };
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

    const InputParseError = error{
        InvalidSequence,
        UnfinishedSequence,
    } || std.mem.Allocator.Error;

    fn parseInput(input: []const u8, allocator: std.mem.Allocator) InputParseError![]u8 {
        // length of result will always be less than or equal to length of input
        var result: std.ArrayListUnmanaged(u8) = try .initCapacity(allocator, input.len);
        errdefer result.deinit(allocator);

        var index: usize = 0;
        while (index < input.len) : (index += 1) {
            if (input[index] == '\\') {
                index += 1;
                if (index >= input.len)
                    return InputParseError.UnfinishedSequence;

                switch (input[index]) {
                    'n' => result.appendAssumeCapacity('\n'),
                    't' => result.appendAssumeCapacity('\t'),
                    'b' => result.appendAssumeCapacity(0x08),
                    '|' => {
                        index += 1;
                        if (index >= input.len)
                            return InputParseError.UnfinishedSequence;

                        switch (input[index]) {
                            // up
                            'i' => result.appendAssumeCapacity('i' + 0x80),
                            // down
                            'k' => result.appendAssumeCapacity('k' + 0x80),
                            // left
                            'j' => result.appendAssumeCapacity('j' + 0x80),
                            // right
                            'l' => result.appendAssumeCapacity('l' + 0x80),
                            // insert
                            'n' => result.appendAssumeCapacity('n' + 0x80),
                            // delete
                            'x' => result.appendAssumeCapacity('x' + 0x80),
                            // home
                            'h' => result.appendAssumeCapacity('h' + 0x80),
                            // end
                            'e' => result.appendAssumeCapacity('e' + 0x80),

                            else => return error.InvalidSequence,
                        }
                    },
                    else => return error.InvalidSequence,
                }
            } else {
                result.appendAssumeCapacity(input[index]);
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    pub fn printFailed(
        reason: FailReason,
    ) !void {
        const stderr = std.io.getStdErr().writer();

        try stderr.print("{s}", .{
            switch (reason) {
                .too_many_args => "Too many arguments\n",
                .too_few_args => "Too few arguments\n",
                .invalid_arg => "Invalid argument\n",
                .invalid_breakpoint_length => "Breakpoint kind list too long\n",
                .invalid_breakpoint_kind => "Invalid breakpoint kind\n",
                .duplicate_breakpoint_kind => "Duplicate breakpoint kind in list\n",
                .invalid_input_sequence => "Invalid input character sequence\n",
                .unfinished_input_sequence => "Expected further characters in input sequence\n",
                .invalid_address_order => "Ending address less than starting address",
                .unknown_command => "Unknown command\n",
                .empty_command => "",
            },
        });
    }
};

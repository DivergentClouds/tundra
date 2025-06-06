const std = @import("std");
const builtin = @import("builtin");

const max_filesize = 0xfff0;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const arg0 = args.next() orelse
        return error.NoArgs;

    var ranges: std.ArrayList(Range) = .init(allocator);
    defer ranges.deinit();

    var filename: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--data")) {
            const range_string = args.next() orelse
                return error.DataOptionWithoutRange;
            try ranges.append(try .parseString(range_string));
        } else {
            if (filename == null) {
                filename = arg;
            } else {
                return error.TooManyFiles;
            }
        }
    }
    if (filename == null) {
        if (ranges.items.len == 0) {
            try printHelp(arg0);
            return;
        } else {
            return error.RangeWithoutFile;
        }
    }

    const memory_file = try std.fs.cwd().openFile(filename.?, .{});

    if (try memory_file.getEndPos() > max_filesize)
        return error.ProgramTooLarge;

    try disassemble(memory_file, ranges.items, allocator);
}

const Range = struct {
    start: u16,
    end: u16,

    fn inside(range: Range, address: u16) bool {
        if (address >= range.start and address <= range.end)
            return true
        else
            return false;
    }
    fn remaining(range: Range, address: u16) ?u16 {
        if (range.inside(address))
            return range.end - address
        else
            return null;
    }

    fn parseString(string: []const u8) !Range {
        const dash_index = std.mem.indexOfScalar(u8, string, '-') orelse
            return error.BadRangeFormat;
        if (dash_index == 0)
            return error.BadRangeStart;

        if (dash_index + 1 >= string.len)
            return error.BadRangeEnd;

        const start = try std.fmt.parseInt(u16, string[0..dash_index], 16);
        const end = try std.fmt.parseInt(u16, string[dash_index + 1 ..], 16);

        if (start > end)
            return error.BadRangeOrder;

        return .{
            .start = start,
            .end = end,
        };
    }
};

fn disassemble(
    memory_file: std.fs.File,
    data_ranges: []const Range,
    allocator: std.mem.Allocator,
) !void {
    const memory_reader = memory_file.reader();
    const stdout = std.io.getStdOut().writer();

    var remaining_data_after: ?u16 = null;
    var address: u16 = 0;
    while (address < try memory_file.getEndPos()) {
        for (data_ranges) |range| {
            if (range.remaining(address)) |remaining| {
                remaining_data_after = remaining;
                break;
            }
        } else {
            remaining_data_after = null;
        }

        if (remaining_data_after) |remaining| {
            if (remaining == 0 or address +| 1 == try memory_file.getEndPos()) {
                try stdout.print("{x:0>4}: {x:0>2}\n", .{
                    address,
                    try memory_reader.readInt(u8, .little),
                });
                address += 1;
            } else {
                try stdout.print("{x:0>4}: {x:0>4}\n", .{
                    address,
                    try memory_reader.readInt(u16, .little),
                });
                address += 2;
            }
        } else {
            const instruction = try readInstruction(memory_file, &address, allocator);
            defer allocator.free(instruction);

            try stdout.print("{s}\n", .{instruction});
        }
    }
}

const Opcode = enum(u3) {
    mov,
    sto,
    add,
    cmp,
    rot,
    @"and",
    nor,
    xor,
};

const Register = enum(u2) {
    a,
    b,
    c,
    pc,
};

// packed structs are ordered with least significant fields on top
const Instruction = packed struct(u8) {
    reg_src: Register,
    deref_src: bool,
    reg_dest: Register,
    opcode: Opcode,
};

/// returned string does not have newline
fn readInstruction(
    memory_file: std.fs.File,
    address: *u16,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const memory_reader = memory_file.reader();

    const byte = try memory_reader.readByte();
    const instruction: Instruction = @bitCast(byte);

    // string cannot be longer than "0000: movi pc, 1fff" (19 characters)
    var byte_list: std.ArrayList(u8) = try .initCapacity(allocator, 19);
    errdefer byte_list.deinit();

    const writer = byte_list.fixedWriter();
    try writer.print(
        "{x:0>4}: {s}{s} {s}, ",
        .{
            address.*, @tagName(instruction.opcode),
            if (instruction.deref_src and instruction.reg_dest == .pc)
                "i"
            else
                "",
            @tagName(instruction.reg_src),
        },
    );

    if (instruction.deref_src and instruction.reg_dest == .pc) {
        try writer.print(
            "{x:0>4}",
            .{
                try memory_reader.readInt(u16, .little),
            },
        );
        address.* += 2;
    } else {
        if (instruction.deref_src) try writer.writeByte('*');
        try writer.writeAll(@tagName(instruction.reg_dest));
    }

    address.* += 1;
    return try byte_list.toOwnedSlice();
}

fn printHelp(arg0: []const u8) !void {
    const stderr = std.io.getStdErr().writer();

    const usage_string =
        \\usage: {s} <memory_file> [[--data <range>]...]
        \\
        \\the --data option is used to mark a region of the file as data and not code
        \\
        \\notes on ranges:
        \\- ranges are of the form start-end, where start is less than end
        \\- ranges are inclusive
        \\- start and end must both be up to 4 digits of hexadecimal
        \\
    ;

    try stderr.print(usage_string, .{arg0});
}

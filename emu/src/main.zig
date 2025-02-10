const std = @import("std");
const Memory = @import("Memory.zig");

pub fn main() !void {}

test {
    std.testing.refAllDeclsRecursive(@This());
}

pub const Error = error{
    InvalidBreakpointLength,
    InvalidBreakpointKind,
    DuplicateBreakpointKind,
};

const Breakpoint = @This();

read: bool,
write: bool,
execute: bool,

const none: Breakpoint = .{
    .read = false,
    .write = false,
    .execute = false,
};

pub fn parse(breakpoint_string: []const u8) Error!Breakpoint {
    if (breakpoint_string.len > 3)
        return error.InvalidBreakpointLength;

    var breakpoint: Breakpoint = .none;

    for (breakpoint_string) |kind| {
        switch (kind) {
            'r' => {
                if (breakpoint.read)
                    return error.DuplicateBreakpointKind
                else
                    breakpoint.read = true;
            },
            'w' => {
                if (breakpoint.write)
                    return error.DuplicateBreakpointKind
                else
                    breakpoint.write = true;
            },
            'x' => {
                if (breakpoint.execute)
                    return error.DuplicateBreakpointKind
                else
                    breakpoint.execute = true;
            },
            else => return error.InvalidBreakpointKind,
        }
    }

    return breakpoint;
}

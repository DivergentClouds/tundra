const std = @import("std");

const DateTime = @This();

/// time since midnight in 2 second intervals
/// do not set directly
time: u16,

/// days since jan 1 1970
/// do not set directly
date: u16,

last_updated: std.time.Instant,

/// the number of 2 second intervals in a day
const day: u16 = 24 * 60 * 30;

pub fn init() !DateTime {
    return .{
        .time = 0,
        .date = 0,
        .last_updated = try .now(),
    };
}

pub fn update(datetime: *DateTime) !void {
    const now: std.time.Instant = try .now();
    const time_elapsed: u16 = @intCast(now.since(datetime.last_updated) / std.time.ns_per_s / 2);

    const new_time, const overflow = @addWithOverflow(datetime.time, time_elapsed);
    if (new_time >= day or overflow == 1) {
        datetime.time = new_time % day;
        datetime.date += 1;
    }

    datetime.last_updated = now;
}

/// `time` is in 2 second intervals since midnight
pub fn setTime(datetime: *DateTime, time: u16) !void {
    if (time >= day)
        return error.InvalidTime;

    datetime.time = time;
    datetime.last_updated = try .now();
}

/// `date` is in days since January 1st 1970
pub fn setDate(datetime: *DateTime, date: u16) !void {
    datetime.date = date;
    datetime.last_updated = try .now();
}

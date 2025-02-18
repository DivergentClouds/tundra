const std = @import("std");
const Memory = @import("Memory.zig");
const Cpu = @import("Cpu.zig");
const Storage = @This();

/// 4.2 ms in cycles
/// based on DEC RK11 timing, adjusted for different disk size
const max_seek_delay = @as(f64, @floatFromInt(Cpu.cycles_per_second)) * 0.0042;
/// 100 μs in cycles
/// mostly pulled out of thin air
const read_write_delay = @as(f64, @floatFromInt(Cpu.cycles_per_second)) * 0.0001;

devices: *[4]?std.fs.File,
ready_delay: *[4]u16, // must be decremented each cycle, 0 means storage device is ready
device_index: u2,

pub const block_size = 2048;

/// returns the number of devices attached
pub fn deviceCount(storage: Storage) u16 {
    for (storage.devices, 0..) |device, index| {
        if (device == null) return index;
    } else return storage.devices.len;
}

pub fn decrementDelay(storage: *Storage) void {
    for (storage.ready_delay) |*delay| {
        delay.* -|= 1;
    }
}

pub fn loadBlock(
    storage: *Storage,
    address: u16,
    memory: Memory,
) !void {
    const device = storage.devices[storage.device_index] orelse
        return error.UnconnectedDevice;

    if (storage.ready_delay[storage.device_index] != 0)
        return error.StorageNotReady;

    var buffer: [block_size]u8 = @splat(0);

    try device.readAll(&buffer);
    memory.writeBlock(address, &buffer);

    storage.ready_delay[storage.device_index] = @intFromFloat(@round(read_write_delay));
}

pub fn storeBlock(
    storage: *Storage,
    address: u16,
    memory: Memory,
) !void {
    const device = storage.devices[storage.device_index] orelse
        return error.UnconnectedDevice;

    if (storage.ready_delay[storage.device_index] != 0)
        return error.StorageNotReady;

    var buffer: [block_size]u8 = undefined;

    memory.readBlock(address, &buffer);
    try device.writeAll(&buffer);

    storage.ready_delay[storage.device_index] = @intFromFloat(@round(read_write_delay));
}

pub fn seek(
    storage: *Storage,
    block_index: u16,
) !void {
    const device = storage.devices[storage.device_index] orelse
        return error.UnconnectedDevice;

    if (storage.ready_delay[storage.device_index] != 0)
        return error.StorageNotReady;

    const old_pos: i32 = @intCast(try device.getPos());
    const new_pos: i32 = block_index * block_size;
    const absolute_distance: i32 = @intCast(@abs(new_pos - old_pos));
    const max_distance: i32 = 0xffff * block_size;

    // in range 0 through 1
    const normalized_distance: f64 = @as(f64, @floatFromInt(max_distance)) /
        @as(f64, @floatFromInt(absolute_distance));

    storage.ready_delay[storage.device_index] = @intFromFloat(@round(
        std.math.lerp(0.0, max_seek_delay, normalized_distance),
    ));

    try device.seekTo(new_pos);
}

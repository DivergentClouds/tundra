const std = @import("std");

const Cpu = @import("Cpu.zig");
const Memory = @import("Memory.zig");
const Storage = @import("Storage.zig");
const Terminal = @import("Terminal.zig");
const Io = @This();

cpu: *Cpu,
memory: *Memory,
storage: *Storage,
terminal: *Terminal,

pub const ReadPort = enum(u16) {
    read_terminal = 0xfff0,
    storage_ready = 0xfff2,
    storage_count = 0xfff4,
    interrupt_handler = 0xfff5,
    interrupt_from = 0xfff6,
    interrupt_kind = 0xfff7,
    enabled_interrupts = 0xfff8,
    bank_map = 0xfff9,
    _,
};

pub const WritePort = enum(u16) {
    write_terminal = 0xfff0,
    seek_storage = 0xfff1,
    store_block = 0xfff2,
    load_block = 0xfff3,
    storage_index = 0xfff4,
    interrupt_handler = 0xfff5,
    enabled_interrupts = 0xfff8,
    bank_map = 0xfff9,
    halt = 0xffff,
    _,
};

pub fn write(
    io: *Io,
    address: WritePort,
    value: u16,
) !void {
    switch (address) {
        .write_terminal => try Terminal.writeChar(@truncate(value)),
        .seek_storage => try io.storage.seek(value),
        .store_block => try io.storage.storeBlock(value, io.memory.*),
        .load_block => try io.storage.loadBlock(value, io.memory),
        .storage_index => io.storage.device_index = @truncate(value),
        .interrupt_handler => io.cpu.interrupt_handler = value,
        .enabled_interrupts => io.cpu.enabled_interrupts = @bitCast(value),
        .bank_map => io.memory.mapRegions(value),
        .halt => io.cpu.running = false,
        _ => return error.InvalidMmioWrite,
    }
}

pub fn read(
    io: Io,
    address: ReadPort,
) !u16 {
    return switch (address) {
        .read_terminal => try io.terminal.readChar(),
        .storage_ready => @intFromBool(io.storage.ready_delay[io.storage.device_index] == 0),
        .storage_count => io.storage.deviceCount(),
        .interrupt_handler => io.cpu.interrupt_handler,
        .interrupt_from => io.cpu.latest_interrupt_from,
        .interrupt_kind => @bitCast(io.cpu.latest_interrupt),
        .enabled_interrupts => @bitCast(io.cpu.enabled_interrupts),
        .bank_map => @bitCast(io.memory.region_bitmap),
        _ => return error.InvalidMmioRead,
    };
}

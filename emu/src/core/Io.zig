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
    get_cursor = 0xfff1,
    storage_ready = 0xfff3,
    storage_count = 0xfff5,
    interrupt_handler = 0xfff6,
    interrupt_from = 0xfff7,
    interrupt_kind = 0xfff8,
    enabled_interrupts = 0xfff9,
    bank_map = 0xfffa,
    alt_registers = 0xfffb,
    _,
};

pub const WritePort = enum(u16) {
    write_terminal = 0xfff0,
    set_cursor = 0xfff1,
    seek_storage = 0xfff2,
    store_block = 0xfff3,
    load_block = 0xfff4,
    storage_index = 0xfff5,
    interrupt_handler = 0xfff6,
    enabled_interrupts = 0xfff9,
    bank_map = 0xfffa,
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
        .set_cursor => try Terminal.setCursorPosition(@intCast(value & 0xff), @intCast(value >> 8)),
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
        .get_cursor => try io.terminal.getCursorPosition(),
        .storage_ready => @intFromBool(io.storage.ready_delay[io.storage.device_index] == 0),
        .storage_count => io.storage.deviceCount(),
        .interrupt_handler => io.cpu.interrupt_handler,
        .interrupt_from => io.cpu.latest_interrupt_from,
        .interrupt_kind => @bitCast(io.cpu.latest_interrupt),
        .enabled_interrupts => @bitCast(io.cpu.enabled_interrupts),
        .bank_map => @bitCast(io.memory.region_bitmap),
        .alt_registers => io.cpu.registers.getModeBitmap(),
        _ => return error.InvalidMmioRead,
    };
}

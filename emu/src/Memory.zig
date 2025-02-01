const std = @import("std");
const builtin = @import("builtin");

/// reserved space at the top of memory for mmio
const mmio_size = 0x10;

/// the largest memory address that isn't mmio
const io_boundary = 0x10000 - mmio_size;

/// amount of memory to be allocated
const memory_size = io_boundary + 1; // need 1 extra byte for reading word from io_boundary - 1

const region_size = 12 * 1024;

const Region = *[region_size]u8;

const Bank = struct {
    region0: Region,
    region1: Region,
    region2: Region,
    region3: Region,

    fn init(allocator: std.mem.Allocator) !Bank {}

    fn deinit(bank: Bank, allocator: std.mem.Allocator) void {}
};

/// remember to @byteSwap when bitcasting to u16 on big endian
const RegionBitmap = packed struct(u16) {
    region3: u4,
    region2: u4,
    region1: u4,
    region0: u4,
};

allocator: std.mem.Allocator,
region_bitmap: RegionBitmap,
active_regions: *[5]Region,
banks: *[16]Bank,

const Memory = @This();

pub const Error = error{
    AddressOutOfRange,
};

pub fn init(
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!Memory {
    const memory: Memory = .{
        .allocator = allocator,
        .region_bitmap = @bitCast(0),
        .active_regions = undefined,
        .banks = undefined,
    };

    var bank_index: u5 = 0;

    errdefer for (0..bank_index) |index| {};

    while (bank_index < 16) : (bank_index += 1) {}
}

pub fn deinit(memory: Memory) void {
    memory.allocator.free(memory.backing_slice);
}

pub fn readByte(memory: Memory, source_location: u16, address: u16) Error!u8 {
    // TODO: check memory protection

    if (address >= io_boundary)
        return Error.AddressOutOfRange;

    return memory.backing_slice[address];
}

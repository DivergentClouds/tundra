const std = @import("std");
const Io = @import("Io.zig");
const Memory = @This();

const block_size = @import("Storage.zig").block_size;

/// reserved space at the top of memory for mmio
const mmio_size = 0x10;

/// the bottom of mmio space
pub const io_boundary = 0x10000 - mmio_size;

pub const region_size = 12 * 1024;
const region_count = 5;

const bank_count = 16;

allocator: std.mem.Allocator,
region_bitmap: RegionBitmap,
active_regions: *[5]*[region_size]u8,
banks: *[bank_count]Bank,

io: Io,

const Bank = struct {
    region0: *[region_size]u8,
    region1: *[region_size]u8,
    region2: *[region_size]u8,
    region3: *[region_size]u8,

    fn init(allocator: std.mem.Allocator) !Bank {
        const region0 = try allocator.alloc(u8, region_size);
        errdefer allocator.free(region0);

        const region1 = try allocator.alloc(u8, region_size);
        errdefer allocator.free(region1);

        const region2 = try allocator.alloc(u8, region_size);
        errdefer allocator.free(region2);

        const region3 = try allocator.alloc(u8, region_size);

        return .{
            .region0 = region0[0..region_size],
            .region1 = region1[0..region_size],
            .region2 = region2[0..region_size],
            .region3 = region3[0..region_size],
        };
    }

    fn deinit(bank: Bank, allocator: std.mem.Allocator) void {
        allocator.free(bank.region0);
        allocator.free(bank.region1);
        allocator.free(bank.region2);
        allocator.free(bank.region3);
    }
};

const RegionBitmap = packed struct(u16) {
    region3: u4,
    region2: u4,
    region1: u4,
    region0: u4,
};

pub fn mapRegions(memory: *Memory, bitmap: u16) void {
    const region_bitmap: RegionBitmap = @bitCast(bitmap);

    memory.region_bitmap = region_bitmap;

    memory.active_regions[0] = memory.banks[region_bitmap.region0].region0;
    memory.active_regions[1] = memory.banks[region_bitmap.region1].region1;
    memory.active_regions[2] = memory.banks[region_bitmap.region2].region2;
    memory.active_regions[3] = memory.banks[region_bitmap.region3].region3;
}

pub fn init(
    allocator: std.mem.Allocator,
    io: Io,
) !Memory {
    const banks = try allocator.alloc(Bank, bank_count);
    errdefer allocator.free(banks);

    var bank_index: u5 = 0;

    errdefer for (0..bank_index) |index| {
        banks[index].deinit(allocator);
    };

    while (bank_index < bank_count) : (bank_index += 1) {
        banks[bank_index] = try .init(allocator);
    }

    const region4 = try allocator.alloc(u8, region_size);
    errdefer allocator.free(region4);

    const active_regions = try allocator.alloc(*[region_size]u8, region_count);

    active_regions[0] = banks[0].region0;
    active_regions[1] = banks[0].region1;
    active_regions[2] = banks[0].region2;
    active_regions[3] = banks[0].region3;
    active_regions[4] = region4[0..region_size];

    return .{
        .allocator = allocator,
        .region_bitmap = @bitCast(@as(u16, 0)),
        .active_regions = active_regions[0..region_count],
        .banks = banks[0..bank_count],
        .io = io,
    };
}

pub fn deinit(memory: Memory) void {
    for (memory.banks) |bank| {
        bank.deinit(memory.allocator);
    }
    memory.allocator.free(memory.banks);

    memory.allocator.free(memory.active_regions[4]);
    memory.allocator.free(memory.active_regions);
}

pub fn readWord(
    memory: Memory,
    address: u16,
) !u16 {
    if (address >= io_boundary) {
        return try memory.io.read(@enumFromInt(address));
    }

    const lsb: u16 = try memory.readByte(address);
    const msb: u16 = try memory.readByte(address + 1);

    return (msb << 8) | lsb;
}

pub fn writeWord(
    memory: *Memory,
    address: u16,
    value: u16,
) !void {
    if (address >= io_boundary) {
        try memory.io.write(@enumFromInt(address), value);
        return;
    }

    const msb: u8 = @intCast(value >> 8);
    const lsb: u8 = @intCast(value & 0xff);

    try memory.writeByte(address, lsb);
    try memory.writeByte(address + 1, msb);
}

pub fn readByte(memory: Memory, address: u16) !u8 {
    // this allows for addressing of 0xfff0, which while not directly allowed
    // is used for reading a word at 0xffef, must special case when reading an
    // instruction
    if (address > io_boundary)
        return error.OutOfRange;

    const address_in_region = address % region_size;
    const region_index = regionIndex(address);

    return switch (region_index) {
        0 => memory.active_regions[0][address_in_region],
        1 => memory.active_regions[1][address_in_region],
        2 => memory.active_regions[2][address_in_region],
        3 => memory.active_regions[3][address_in_region],
        4 => memory.active_regions[4][address_in_region],
        else => unreachable,
    };
}

fn writeByte(
    memory: Memory,
    address: u16,
    value: u8,
) !void {
    // this allows for addressing of 0xfff0, which while not directly allowed
    // is used for writing a word at 0xffef
    if (address > io_boundary)
        return error.OutOfRange;

    const address_in_region = address % region_size;
    const region_index = regionIndex(address);

    if (region_index == 0 and memory.region_bitmap.region0 == 0)
        return error.WriteInRom;

    switch (region_index) {
        0 => memory.active_regions[0][address_in_region] = value,
        1 => memory.active_regions[1][address_in_region] = value,
        2 => memory.active_regions[2][address_in_region] = value,
        3 => memory.active_regions[3][address_in_region] = value,
        4 => memory.active_regions[4][address_in_region] = value,
        else => unreachable,
    }
}

pub fn readBlock(
    memory: Memory,
    address: u16,
    buffer: *[block_size]u8,
) !void {
    const end_address = address +| block_size;

    if (end_address >= io_boundary)
        return error.OutOfRange;

    const start_region = regionIndex(address);
    const end_region = regionIndex(end_address);

    const start_address_in_region = address % region_size;
    const end_address_in_region = end_address % region_size;
    if (start_region == end_region) {
        @memcpy(
            buffer,
            memory.active_regions[start_region][start_address_in_region..end_address_in_region],
        );
    } else {
        const start_region_remaining = region_size - start_address_in_region;
        @memcpy(
            buffer[0..start_region_remaining],
            memory.active_regions[start_region][start_address_in_region..region_size],
        );
        @memcpy(
            buffer[start_region_remaining..],
            memory.active_regions[end_region][0..end_address_in_region],
        );
    }
}

pub fn writeBlock(
    memory: *Memory,
    address: u16,
    buffer: *const [block_size]u8,
) !void {
    const end_address = address +| block_size;

    if (end_address >= io_boundary)
        return error.OutOfRange;

    const start_region = regionIndex(address);
    const end_region = regionIndex(end_address);

    const start_address_in_region = address % region_size;
    const end_address_in_region = end_address % region_size;
    if (start_region == end_region) {
        @memcpy(
            memory.active_regions[start_region][start_address_in_region..end_address_in_region],
            buffer,
        );
    } else {
        const start_region_remaining = region_size - start_address_in_region;
        @memcpy(
            memory.active_regions[start_region][start_address_in_region..region_size],
            buffer[0..start_region_remaining],
        );
        @memcpy(
            memory.active_regions[end_region][0..end_address_in_region],
            buffer[start_region_remaining..],
        );
    }
}

pub fn writeRom(memory: *Memory, rom_data: []const u8) !void {
    if (rom_data.len > region_size)
        return error.RomTooLarge;

    @memcpy(memory.banks[0].region0[0..rom_data.len], rom_data);
}

pub fn regionIndex(address: u16) u3 {
    return switch (address) {
        0 * region_size...1 * region_size - 1 => 0,
        1 * region_size...2 * region_size - 1 => 1,
        2 * region_size...3 * region_size - 1 => 2,
        3 * region_size...4 * region_size - 1 => 3,
        4 * region_size...0xffff => 4,
    };
}

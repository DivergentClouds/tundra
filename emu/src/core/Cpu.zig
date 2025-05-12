const std = @import("std");
const Memory = @import("Memory.zig");
const Terminal = @import("Terminal.zig");
const Cpu = @This();

enabled_interrupts: Interrupts,
interrupt_handler: u16,
latest_interrupt: Interrupts,
latest_interrupt_from: u16,

registers: Registers,
instruction_state: InstructionState,

cmp_flag: bool,
clock_counter: u16,
previous_clock_counter: u16,

keyboard_clock_counter: u16,

/// informational, checked by main interpreter loop
running: bool,

pub const init: Cpu = .{
    .enabled_interrupts = .init,
    .interrupt_handler = 0,
    .latest_interrupt = .init,
    .latest_interrupt_from = 0,

    .registers = .init,
    .instruction_state = .fetch,

    .cmp_flag = false,
    .clock_counter = 0,
    .previous_clock_counter = 0,

    .keyboard_clock_counter = 0,

    .running = true,
};

// 5 MHz
pub const cycles_per_second = 5 * 1_000_000;
pub const ns_per_cycle = std.time.ns_per_s / cycles_per_second;

const keyboard_interrupts_per_second = 100;
const cycles_per_keyboard_interrupt = cycles_per_second / keyboard_interrupts_per_second;

pub const Interrupts = packed struct(u16) {
    read_protection: bool = false,
    write_protection: bool = false,
    exec_protection: bool = false,
    timer: bool = false,
    keyboard: bool = false,
    _: u11 = 0,

    const init: Interrupts = .{};

    pub fn format(
        interrupts: Interrupts,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var interrupt_printed = false;
        inline for (@typeInfo(Interrupts).@"struct".fields) |field| {
            const field_contents = @field(interrupts, field.name);

            const interrupt_occured = if (@TypeOf(field_contents) == bool)
                field_contents
            else
                false;

            if (interrupt_occured) {
                if (interrupt_printed) {
                    try writer.writeAll(", ");
                }
                try writer.writeAll(field.name);
                interrupt_printed = true;
            }
        }
    }
};

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

pub const RegisterKind = enum(u2) {
    a,
    b,
    c,
    pc,
};

const Instruction = packed struct(u8) {
    source: RegisterKind,
    deref_source: bool,
    destination: RegisterKind,
    opcode: Opcode,

    pub fn format(
        instruction: Instruction,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            "{s} {s}, {s}{s}",
            .{
                @tagName(instruction.opcode),
                @tagName(instruction.destination),
                if (instruction.deref_source)
                    "*"
                else
                    "",
                @tagName(instruction.source),
            },
        );
    }
};

const RegisterMode = enum {
    primary,
    secondary,
};

const RegisterContents = struct {
    mode: RegisterMode,
    primary: u16,
    secondary: u16,

    const init: RegisterContents = .{
        .mode = .primary,
        .primary = 0,
        .secondary = 0,
    };
};

pub const Registers = struct {
    a: RegisterContents,
    b: RegisterContents,
    c: RegisterContents,
    pc: u16 = 0,

    const init: Registers = .{
        .a = .init,
        .b = .init,
        .c = .init,
        .pc = 0,
    };

    pub fn format(
        registers: Registers,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: std.io.AnyWriter,
    ) !void {
        if (fmt.len == 0) {
            try writer.print("a = ", .{});
            try std.fmt.formatIntValue(registers.a, "x", options, writer);

            try writer.print(", b = ", .{});
            try std.fmt.formatIntValue(registers.b, "x", options, writer);

            try writer.print(", c = ", .{});
            try std.fmt.formatIntValue(registers.c, "x", options, writer);

            try writer.print("d = ", .{});
            try std.fmt.formatIntValue(registers.pc, "x", options, writer);
        } else if (comptime std.mem.eql(u8, fmt, "a")) {
            try std.fmt.formatIntValue(registers.a, "x", options, writer);
        } else if (comptime std.mem.eql(u8, fmt, "b")) {
            try std.fmt.formatIntValue(registers.b, "x", options, writer);
        } else if (comptime std.mem.eql(u8, fmt, "c")) {
            try std.fmt.formatIntValue(registers.c, "x", options, writer);
        } else if (comptime std.mem.eql(u8, fmt, "pc")) {
            try std.fmt.formatIntValue(registers.pc, "x", options, writer);
        } else {
            std.fmt.invalidFmtError(fmt, registers);
        }
    }

    pub fn get(
        registers: Registers,
        register: RegisterKind,
    ) u16 {
        return switch (register) {
            .a => if (registers.a.mode == .primary)
                registers.a.primary
            else
                registers.a.secondary,
            .b => if (registers.b.mode == .primary)
                registers.b.primary
            else
                registers.b.secondary,
            .c => if (registers.c.mode == .primary)
                registers.c.primary
            else
                registers.c.secondary,
            .pc => registers.pc,
        };
    }

    /// returns any interrupts that were triggered
    fn set(
        register: RegisterKind,
        value: u16,
        jump: bool,
        cpu: *Cpu,
    ) Interrupts {
        if (register == .pc) {
            if (cpu.cmp_flag and jump) {
                cpu.cmp_flag = false;
            } else {
                const interrupt = checkPermissionInterrupt(cpu.*, value, .execute);
                if (interrupt != Interrupts{}) {
                    return interrupt;
                }
                cpu.registers.pc = value;
            }
        } else setNoCheck(register, value, cpu);

        return Interrupts{};
    }

    pub fn setNoCheck(register: RegisterKind, value: u16, cpu: *Cpu) void {
        switch (register) {
            .a => if (cpu.registers.a.mode == .primary) {
                cpu.registers.a.primary = value;
            } else {
                cpu.registers.a.secondary = value;
            },
            .b => if (cpu.registers.b.mode == .primary) {
                cpu.registers.b.primary = value;
            } else {
                cpu.registers.b.secondary = value;
            },
            .c => if (cpu.registers.c.mode == .primary) {
                cpu.registers.c.primary = value;
            } else {
                cpu.registers.c.secondary = value;
            },
            .pc => cpu.registers.pc = value,
        }
    }

    fn setMode(
        registers: *Registers,
        register: RegisterKind,
        mode: RegisterMode,
    ) void {
        switch (register) {
            .a => registers.a.mode = mode,
            .b => registers.b.mode = mode,
            .c => registers.c.mode = mode,
            .pc => {},
        }
    }
};

const InstructionWithData = struct {
    instruction: Instruction,
    /// null if instruction.deref_source == false
    data: ?u16 = null,

    pub fn format(
        instruction_with_data: InstructionWithData,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            "{}",
            .{
                instruction_with_data.instruction,
            },
        );

        if (instruction_with_data.data) |data| {
            try writer.print(" ({x:0>4})", .{data});
        }
    }
};

/// active tag is the next micro-op to do
pub const InstructionState = union(enum) {
    /// active if an interrupt triggered during the last instruction
    interrupt: Interrupts,
    /// read a byte from memory
    fetch,
    /// pc is incremented by 2 if dereferenced at the end of this
    read_memory: Instruction,
    // memory is written here
    execute: InstructionWithData,
};

pub fn clockDelay(current_timestamp: *i128, cycles: u16) void {
    var next_timestamp = std.time.nanoTimestamp();
    while (current_timestamp.* + ns_per_cycle * cycles > next_timestamp) {
        std.time.sleep(cycles); // this is more precise than just calling sleep once
        next_timestamp = std.time.nanoTimestamp();
    }

    current_timestamp.* = next_timestamp;
}

/// returns the number of cycles the tick took
pub fn doTick(
    cpu: *Cpu,
    memory: *Memory,
    terminal: *Terminal, // for checking keyboard interrupt
) !u16 {
    switch (cpu.instruction_state) {
        .interrupt => |interrupt| {
            cpu.latest_interrupt_from = cpu.registers.pc;
            cpu.registers.pc = cpu.interrupt_handler;
            cpu.latest_interrupt = interrupt;
            cpu.instruction_state = .fetch;

            return 1;
        },
        .fetch => return try cpu.fetch(memory.*, terminal),
        .read_memory => |instruction| return try cpu.dereferenceSource(
            memory.*,
            instruction,
        ),
        .execute => |instruction_with_data| return try execute(
            cpu,
            memory,
            instruction_with_data,
        ),
    }
}

// returns cycles taken
fn fetch(cpu: *Cpu, memory: Memory, terminal: *Terminal) !u16 {
    const interrupt = try cpu.checkAsyncInterrupt(terminal);

    if (interrupt != Interrupts{}) {
        cpu.instruction_state = .{ .interrupt = interrupt };
        return 0; // interrupt triggers happen "asynchronously"
    }
    const instruction = try readInstruction(
        memory,
        cpu.registers.pc,
    );

    const triggered_interrupts = Registers.set(
        .pc,
        cpu.registers.pc + 1, // pc can never be above 0xfff0, no need to wrap
        false,
        cpu,
    );

    if (triggered_interrupts == Interrupts{}) {
        if (instruction.deref_source) {
            cpu.instruction_state = .{ .read_memory = instruction };
        } else {
            cpu.instruction_state = .{ .execute = .{ .instruction = instruction } };
        }
    } else if (triggered_interrupts == Interrupts{ .exec_protection = true }) {
        cpu.instruction_state = .{ .interrupt = triggered_interrupts };

        return 1; // no instruction was fetched
    } else {
        std.debug.panic("Unexpected interrupt(s) during fetch: {}\r\n", .{interrupt});
    }

    return 2; // memory access takes 2 cycles
}

fn dereferenceSource(
    cpu: *Cpu,
    memory: Memory,
    instruction: Instruction,
) !u16 {
    const source_register_value = cpu.registers.get(instruction.source);

    // we know instruction.deref_source is true
    const interrupt = checkPermissionInterrupt(cpu.*, source_register_value, .write);

    if (interrupt != Interrupts{}) {
        cpu.instruction_state = .{ .interrupt = interrupt };
        return 1;
    }

    const word = try memory.readWord(source_register_value);

    if (instruction.source == .pc) {
        const triggered_interrupts = Registers.set(
            .pc,
            cpu.registers.pc + 2,
            false,
            cpu,
        );

        if (triggered_interrupts == Interrupts{ .exec_protection = true }) {
            cpu.instruction_state = .{ .interrupt = triggered_interrupts };

            return 1; // no instruction was fetched
        } else if (triggered_interrupts != Interrupts{}) {
            std.debug.panic("Unexpected interrupt during post-literal increment\n", .{});
        }
    }

    cpu.instruction_state = .{
        .execute = .{
            .instruction = instruction,
            .data = word,
        },
    };
    return 2;
}

fn execute(
    cpu: *Cpu,
    memory: *Memory,
    instruction_with_data: InstructionWithData,
) !u16 {
    const src_data = instruction_with_data.data orelse
        cpu.registers.get(instruction_with_data.instruction.source);

    const dest = instruction_with_data.instruction.destination;

    const dest_data = cpu.registers.get(dest);

    defer cpu.instruction_state = .fetch;

    switch (instruction_with_data.instruction.opcode) {
        .mov => {
            if (dest == instruction_with_data.instruction.source and
                !instruction_with_data.instruction.deref_source)
            {
                cpu.registers.setMode(dest, .primary);
            }

            const interrupt = Registers.set(
                dest,
                src_data,
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
        .sto => {
            const interrupt = checkPermissionInterrupt(cpu.*, dest_data, .write);

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }

            try memory.writeWord(
                dest_data,
                src_data,
            );

            return 2;
        },
        .add => {
            const interrupt = Registers.set(
                dest,
                dest_data +% src_data,
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
        .cmp => {
            const signed_dest_data: i16 = @bitCast(dest_data);
            const signed_src_data: i16 = @bitCast(src_data);

            if (signed_dest_data > signed_src_data) {
                cpu.cmp_flag = true;
            } else {
                cpu.cmp_flag = false;
            }
        },
        .rot => {
            const rotated_dest_data = std.math.rotl(
                u16,
                dest_data,
                src_data,
            );

            const interrupt = Registers.set(
                dest,
                rotated_dest_data,
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
        .@"and" => {
            if (dest == instruction_with_data.instruction.source and
                !instruction_with_data.instruction.deref_source)
            {
                cpu.registers.setMode(dest, .secondary);
            }

            const interrupt = Registers.set(
                dest,
                dest_data & src_data,
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
        .nor => {
            const interrupt = Registers.set(
                dest,
                ~(dest_data | src_data),
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
        .xor => {
            const interrupt = Registers.set(
                dest,
                dest_data ^ src_data,
                true,
                cpu,
            );

            if (interrupt != Interrupts{}) {
                cpu.instruction_state = .{ .interrupt = interrupt };
                return 1;
            }
        },
    }

    return 1;
}

fn readInstruction(
    memory: Memory,
    address: u16,
) !Instruction {
    // special case to handle attempting to read a single byte at io_boundary.
    // since this is the only place a single byte can be read, so it's fine to
    // special case this here
    if (address >= Memory.io_boundary)
        return error.OutOfRange;

    const byte = memory.readByte(address) catch |err| switch (err) {
        error.OutOfRange => unreachable, // checked earlier
        else => return err, // in case readByte ends up returning other errors
    };
    const inst: Instruction = @bitCast(byte);

    return inst;
}

fn checkAsyncInterrupt(cpu: *Cpu, terminal: *Terminal) !Interrupts {
    if (Memory.regionIndex(cpu.registers.pc) == 4)
        return Interrupts{};

    defer cpu.previous_clock_counter = cpu.clock_counter;

    // clock interrupt on clock_counter overflow
    if (cpu.enabled_interrupts.timer and
        cpu.clock_counter < cpu.previous_clock_counter)
    {
        return Interrupts{ .timer = true };
    } else if (cpu.enabled_interrupts.keyboard and
        cpu.keyboard_clock_counter >= cycles_per_keyboard_interrupt and
        try terminal.inputReady())
    {
        cpu.keyboard_clock_counter = 0;
        return Interrupts{ .keyboard = true };
    }

    return Interrupts{};
}

fn checkPermissionInterrupt(
    cpu: Cpu,
    address: u16,
    kind: enum { read, write, execute },
) Interrupts {
    const pc_region = Memory.regionIndex(cpu.registers.pc);
    const address_region = Memory.regionIndex(address);

    const permission_region = pc_region < 4 and address_region == 4;

    switch (kind) {
        .read => if (permission_region and cpu.enabled_interrupts.read_protection)
            return Interrupts{ .read_protection = true },
        .write => if (permission_region and cpu.enabled_interrupts.write_protection)
            return Interrupts{ .write_protection = true },
        .execute => if (permission_region and cpu.enabled_interrupts.exec_protection)
            return Interrupts{ .exec_protection = true },
    }

    return Interrupts{};
}

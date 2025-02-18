const std = @import("std");
const Memory = @import("Memory.zig");
const Terminal = @import("Terminal.zig");
const Cpu = @This();

enabled_interrupts: Interrupts = .{},
interrupt_handler: u16 = 0,
latest_interrupt: Interrupts = .{},
latest_interrupt_from: u16 = 0,

registers: Registers = .{},
instruction_state: InstructionState = .fetch,

cmp_flag: bool = false,
clock_counter: u16 = 0,
previous_clock_counter: u16 = 0,

/// informational, checked by main interpreter loop
running: bool = true,

/// 5 MHz
pub const cycles_per_second = 5 * 1_000_000;

pub const Interrupts = packed struct(u16) {
    read_protection: bool = false,
    write_protection: bool = false,
    exec_protection: bool = false,
    timer: bool = false,
    keyboard: bool = false,
    _: u11 = 0,
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

const RegisterKind = enum(u2) {
    a,
    b,
    c,
    pc,
};

const Instruction = packed struct(u8) {
    opcode: Opcode,
    destination: RegisterKind,
    deref_source: bool,
    source: RegisterKind,
};

const Registers = struct {
    a: u16 = 0,
    b: u16 = 0,
    c: u16 = 0,
    pc: u16 = 0,

    fn get(
        registers: Registers,
        register: RegisterKind,
    ) u16 {
        return switch (register) {
            .a => registers.a,
            .b => registers.b,
            .c => registers.c,
            .pc => registers.pc,
        };
    }

    /// returns any interrupts that were triggered
    fn set(
        register: RegisterKind,
        value: u16,
        cpu: *Cpu,
    ) Interrupts {
        switch (register) {
            .a => cpu.registers.a = value,
            .b => cpu.registers.b = value,
            .c => cpu.registers.c = value,
            .pc => {
                if (cpu.cmp_flag) {
                    cpu.cmp_flag.* = false;
                } else {
                    if (cpu.enabled_interrupts.exec_protection and
                        Memory.regionIndex(cpu.registers.pc) <= 3 and
                        Memory.regionIndex(value) == 4)
                    {
                        return Interrupts{ .exec_protection = true };
                    }
                    cpu.registers.pc = value;
                }
            },
        }
        return Interrupts{};
    }
};

const InstructionWithData = struct {
    instruction: Instruction,
    /// null if instruction.deref_source == false
    word: ?u16 = null,
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

/// returns the number of cycles the tick took
fn doTick(
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
        .fetch => return try cpu.fetch(memory, terminal),
        .read_memory => |instruction| return try cpu.dereferenceSource(
            memory,
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
    if (try cpu.checkInterrupt(terminal)) |interrupt| {
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
        std.debug.panic("Unexpected interrupt during fetch\n", .{});
    }

    return 2; // memory access takes 2 cycles
}

fn dereferenceSource(
    cpu: *Cpu,
    memory: Memory,
    instruction: Instruction,
) !u16 {
    const source_register_value = cpu.registers.get(instruction.source);

    if (cpu.enabled_interrupts.read_protection and
        Memory.regionIndex(cpu.registers.pc) <= 3 and
        Memory.regionIndex(source_register_value +| 1) == 4) // add 1 to check the upper byte of the word
    {
        cpu.instruction_state = .{ .interrupt = Interrupts{ .read_protection = true } };
        return 1; // memory was not read
    }

    // we know instruction.deref_source is true
    const word = try memory.readWord(source_register_value);

    if (instruction.source == .pc) {
        const triggered_interrupts = Registers.set(
            .pc,
            source_register_value + 2, // pc
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
            .word = word,
        },
    };
    return 2;
}

fn execute(
    cpu: *Cpu,
    memory: Memory,
    instruction_with_data: InstructionWithData,
) !u16 {
    const src_data = instruction_with_data.word orelse
        cpu.registers.get(instruction_with_data.instruction.source);

    const dest = instruction_with_data.instruction.destination;

    const dest_data = cpu.registers.get(dest);

    switch (instruction_with_data.instruction.opcode) {
        .mov => {
            Registers.set(
                dest,
                src_data,
                cpu,
            );
        },
        .sto => {
            try memory.writeWord(
                dest_data,
                src_data,
            );

            return 2;
        },
        .add => {
            Registers.set(
                dest,
                dest_data +% src_data,
                cpu,
            );
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
            const rotated_dest_data = std.math.rotr(
                u16,
                dest_data,
                src_data,
            );

            Registers.set(
                dest,
                rotated_dest_data,
                cpu,
            );
        },
        .@"and" => {
            Registers.set(
                dest,
                dest_data & src_data,
                cpu,
            );
        },
        .nor => {
            Registers.set(
                dest,
                ~(dest_data | src_data),
                cpu,
            );
        },
        .xor => {
            Registers.set(
                dest,
                dest_data ^ src_data,
                cpu,
            );
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

    return @bitCast(memory.readByte(address) catch |err| switch (err) {
        error.OutOfRange => unreachable, // checked earlier
        else => return err, // in case readByte ends up returning other errors
    });
}

fn checkInterrupt(cpu: *Cpu, terminal: *Terminal) !?Interrupts {
    if (Memory.regionIndex(cpu.registers.pc) == 4)
        return null;

    defer cpu.previous_clock_counter = cpu.clock_counter;

    if (cpu.enabled_interrupts.timer and cpu.clock_counter < cpu.previous_clock_counter) {
        return Interrupts{ .timer = true };
    } else if (cpu.enabled_interrupts.keyboard and try terminal.inputReady()) {
        return Interrupts{ .keyboard = true };
    }

    return null;
}

==========
= Tundra =
==========


ISA
===

Binary Format
-------------
OOO WW DRR

O -> opcode
W -> register (usually destination)
D -> dereference the following register if 1
R -> register (usually source)

Registers
---------
A  = 00
B  = 01
C  = 10
PC = 11


Dereferenced registers
----------------------
*A  = 100
*B  = 101
*C  = 110
*PC = 111


Instructions
------------
MOV = 000 WW DRR // set W to R
ADD = 001 WW DRR // set W to W+R (signed)
NEG = 010 WW DRR // set W to 0-R (signed)
STO = 011 WW DRR // store R at memory[W] and memory[W + 1]
CMP = 100 WW DRR // if W is greater than R (signed), ignore the next attempt to
	modify PC, otherwise allow the next attempt to modify the PC, the PC is
	mutable by default
SHF = 101 WW DRR // set W to W bitshifted by R bits
	(leftshift if R is negative, rightshift if R is positive)
AND = 110 WW DRR // set W to R&W
NOR = 111 WW DRR // set W to ~(R|W)


Notes
-----
- data is 16-bit little endian
- dereferencing R will load memory[R] and memory[R + 1]
- PC is incremented by 1 after an instruction is fetched
- dereferencing PC will increment it by 2 after fetch but before execution

MMIO
====

Memory Map
----------
|---------|------------|-----------------------------------|
| address | read/write | effect                            |
|---------|------------|-----------------------------------|
| 0xfff0  | read       | reads 1 if input is available,    |
|         |            | 0 otherwise                       |
|---------|------------|-----------------------------------|
| 0xfff1  | read       | waits until input is available,   |
|         |            | then reads input into LSB,        |
|         |            | clearing MSB                      |
|---------|------------|-----------------------------------|
| 0xfff2  | write      | writes LSB to output              |
|---------|------------|-----------------------------------|
| 0xfff3  | read/write | stores the least significant word |
|         |            | of the 24-bit storage seek        |
|         |            | address                           |
|---------|------------|-----------------------------------|
| 0xfff4  | read/write | stores LSB as the most            |
|         |            | significant byte of the 24-bit    |
|         |            | storage seek address. reads into  |
|         |            | LSB and clears MSB                |
|---------|------------|-----------------------------------|
| 0xfff5  | read/write | stores the chunk size for storage |
|         |            | access                            |
|---------|------------|-----------------------------------|
| 0xfff6  | write      | write a chunk from storage at the |
|         |            | seek address into memory at the   |
|         |            | given address                     |
|---------|------------|-----------------------------------|
| 0xfff7  | write      | write a chunk from memory at the  |
|         |            | the given address into storage at |
|         |            | the seek address                  |
|---------|------------|-----------------------------------|
| 0xffff  | write      | halt execution                    |
|---------|------------|-----------------------------------|


Notes
-----
- addresses 0xfff0 and above are reserved for mmio and may not be executed
- attempting to read/write memory in and above the mmio range via storage access
	is a no-op
- attempting to read undefined storage will read 0
- seek address and chunk size default to 0
- only the 24-bit address range of storage may be written to
- if EOF is recieved when reading input, then 0 will be read


Emulator
========

Notes
-----
- enter must be pressed before input may be read


Assembler
=========

Assembling
----------
to assemble a tundra program, use fasmg (https://flatassembler.net/) and
include either 'tundra-core.inc' or 'tundra-extra.inc' (which includes
tundra-core) at the top of your file. assembly is not case-sensitive.
semicolons start line comments


Tundra-Core
-----------
tundra-core.inc includes the instruction set along with macros that treat R as
an immediate. To use them, suffix an instruction name with 'I'. As an example:

	MOVI A, -1

is equivalent to:

	MOV A, *PC
	0xFFFF


Tundra-Extra
------------
tundra-extra.inc includes tundra-core along with the following macros ('src'
marks a register that may be dereferenced, 'dest' marks one that may not be,
and 'imm' marks a 16-bit immediate:

	; moves a register to PC
	JMP src

	; moves an immediate to PC
	JMPI imm

	; jump to src if dest1 and dest2 are equal
	JEQ dest1, dest2, src

	; jump to imm if dest1 and dest2 are equal
	JEQI dest1, dest2, imm

	; jump to src if dest1 and dest2 are not equal
	JNE dest1, dest2, src

	; jump to imm if dest1 and dest2 are not equal
	JNEI, dest1, dest2, imm

	; this macro must be called before the first time a macro that uses the stack
	; 	is called
	; macros that use the stack reserve C as the stack pointer
	; sets C to 0xFFEE
	STACK_INIT

	; pushes a register to the stack
	PUSH src

	; pushes an immediate to the stack
	PUSHI imm
	
	; pops an element from the stack into dest
	POP dest

	; removes the top element of the stack
	DROP

	; pushes the next address to the stack and jumps to the value of src
	; has no effect if CMP flag is set
	CALL src
	
	; pushes the next address to the stack and jumps to the value of imm
	; has no effect if CMP flag is set
	CALLI src

	; pops an element of the stack into PC
	RET

in addition, tundra-extra.inc defines following constants:

	MMIO = 0xFFF0

	MMIO.INPUT_AVAILABLE = 0xFFF0

	MMIO.READ_CHAR = 0xFFF1

	MMIO.WRITE_CHAR = 0xFFF2

	MMIO.SEEK_LSW = 0xFFF3

	MMIO.SEEK_MSB = 0xFFF4

	MMIO.CHUNK_SIZE = 0xFFF5

	MMIO.READ_CHUNK = 0xFFF6

	MMIO.WRITE_CHUNK = 0xFFF7

	MMIO.HALT = 0xFFFF


License
=======

Notes
-----
- The contents of this repository are licensed under the 3-Clause BSD license
	unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
	license

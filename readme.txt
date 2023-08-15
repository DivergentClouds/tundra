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

memory map
----------
|---------|------------|-----------------------------------|
| address | read/write | effect                            |
|---------|------------|-----------------------------------|
| 0xfff0  | read       | reads 1 if input is available,    |
|         |            | reads 0 otherwise                 |
|---------|------------|-----------------------------------|
| 0xfff1  | read       | waits until input is available,   |
|         |            | then reads LSB from input,        |
|         |            | clearing MSB                      |
|---------|------------|-----------------------------------|
| 0xfff2  | write      | writes LSB to output              |
|---------|------------|-----------------------------------|
| 0xffff  | write      | halts                             |
|---------|------------|-----------------------------------|


Notes
-----
- addresses 0xfff0 and above are reserved for mmio and may not be executed


Emulator
========

Notes
-----
- enter must be pressed before input may be read
- the emulator on windows will currently only detect enter within the first
  4096 input events


Assembler
=========

assembling
----------
to assemble a tundra program, use fasmg (https://flatassembler.net/) and
include either 'tundra-core.inc' or 'tundra-extra.inc' (which includes
tundra-core) at the top of your file. assembly is not case-sensitive.
semicolons start line comments


tundra-core
-----------
tundra-core.inc includes the instruction set along with macros that treat R as
an immediate. To use them, suffix an instruction name with 'I'. As an example:

	MOVI A, -1

is equivalent to:

	MOV A, *PC
	0xFFFF


tundra-extra
------------
tundra-extra.inc includes tundra-core along with the following macros ('src'
marks a register that may be dereferenced, 'dest' marks one that may not be,
and 'imm' marks a 16-bit immediate:

	; moves a register to PC
	JMP src

	; moves an immediate to PC
	JMPI imm

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

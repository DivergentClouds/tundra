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
STO = 001 WW DRR // store R starting at memory[W] 
ADD = 010 WW DRR // set W to W+R (wrapping)
CMP = 011 WW DRR // if W is greater than R (signed), ignorethe next attempt to
	modify PC, otherwise allow the next attempt to modify the PC, the PC is
	mutable by default
SHF = 100 WW DRR // set W to W bitshifted by (R & 0xf) bits,
  if bit 4 of R is set, shift left, otherwise shift right,
  if bit 5 of R is set, perform a rotation rather than a shift,
  if bit 6 of R is set, sign extend the result, incompatible with bits 4 and 5
AND = 101 WW DRR // set W to R&W
NOR = 110 WW DRR // set W to ~(R|W)
XOR = 111 WW DRR // set W to R^W


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
|         |            | given address, increment seek     |
|         |            | address by chunk size             |
|---------|------------|-----------------------------------|
| 0xfff7  | write      | write a chunk from memory at the  |
|         |            | the given address into storage at |
|         |            | the seek address, increment seek  |
|         |            | address by chunk size             |
|---------|------------|-----------------------------------|
| 0xfff8  | read       | reads the number of attached      |
|         |            | storage devices                   |
|---------|------------|-----------------------------------|
| 0xfff9  | write      | set which storage device to       |
|         |            | access, 0-indexed.                |
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
- if EOF is recieved when reading input, then -1 will be read


Emulator
========

Usage
-----
	tundra <memory_file> [[-s storage_file] ...] [-d]

Notes
-----
- at most 3 storage devices may be attached
- if the '-d' flag is set, each instruction will be printed as it is run
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
and 'imm' marks a 16-bit immediate. note that 'src' may not be '*pc' and
'dest' may not be 'pc'):

	; halts execution
	HALT

  ; set dest to the bitwise not of dest
  NOT dest

  ; set dest to the bitwise or dest and src
  OR dest, src

  ; set dest to the bitwise or dest and imm
  ORI dest, imm

  ; set dest to dest bitshifted to the right by imm, shifting in 0s
  SHRI dest, imm

  ; set dest to dest bitshifted to the left by imm, shifting in 0s
  SHLI dest, imm

  ; set dest to dest bitshifted to the right by imm, shifting in copies of the
  ; sign bit
  ASRI dest, imm

  ; set dest to dest rotated to the right by imm
  RTRI dest, imm

  ; set dest to dest rotated to the left by imm
  RTLI dest, imm

  ; set dest to the two's complement negation of dest
  NEG dest

  ; subtract src from dest
  SUB dest, src

  ; subtract imm from dest
  SUBI dest, imm

	; set PC to src
  ; has no effect if CMP flag is set
	JMP src

	; set PC to imm
	; has no effect if CMP flag is set
	JMPI imm

	; jump to src if dest1 and dest2 are equal
	JEQ dest1, dest2, src

	; jump to imm if dest1 and dest2 are equal
	JEQI dest1, dest2, imm

	; jump to src if dest1 and dest2 are not equal
	JNE dest1, dest2, src

	; jump to imm if dest1 and dest2 are not equal
	JNEI, dest1, dest2, imm

	; jump to src2 if dest and src1 are equal, assert dest and src1 are positive
	JEQP dest, src1, src2

	; jump to imm if dest and src are equal, assert dest and src are positive
	JEQPRI dest, src, imm

	; jump to imm2 if dest and imm1 are equal, assert dest and imm1 are positive
	JEQPI dest, imm1, imm2

	; jump to src2 if dest is not equal to src1, assert dest and src1 are positive
	JNEP dest, src1, src2

	; jump to imm if dest is not equal to src, assert dest and src are positive
	JNEPRI dest, src, imm

	; jump to imm2 if dest is not equal to imm1, assert dest and imm1 are positive
	JNEPI  dest, imm1, imm2

	; this macro must be called before the first time a macro that uses the stack
	; 	is called
	; macros that use the stack reserve C as the stack pointer
	; sets C to STACK_BASE
	STACK_INIT

	; push src to the stack
  PUSH src

	; push imm to the stack
	PUSHI imm
	
	; pop a word from the stack into dest
	POP dest

  ; pop a word of the stack into PC
  POPJ

	; remove the top src bytes of the stack
	DROP src

	; remove the top imm bytes of the stack
	DROPI imm

	; copy a value that is src items deep in the stack to dest
	PEEK dest, src

	; copy a value that is imm items deep in the stack to dest
	PEEKI dest, imm

	; push the next address to the stack and jumps to the value of src
	; has no effect if CMP flag is set
	CALL src
	
	; push the next address to the stack and jumps to the value of imm
	; has no effect if CMP flag is set
	CALLI src

	; pop a word into dest before dropping src bytes from the stack followed by
  ; jumping to dest
  ; has no effect if CMP flag is set
	RET src

	; pop a word into dest before dropping imm bytes from the stack followed by
  ; jumping to dest
  ; has no effect if CMP flag is set
	RETI imm

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

	MMIO.STORAGE_COUNT = 0xFFF8

	MMIO.STORAGE_INDEX = 0xFFF9

	MMIO.HALT = 0xFFFF

	STACK_BASE = 0xFFEE


License
=======

Notes
-----
- the contents of this repository are licensed under the 3-Clause BSD license
	unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
	license

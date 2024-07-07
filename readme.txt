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
CMP = 011 WW DRR // if W is greater than R (signed), ignore the next attempt to
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
|=========|============|===================================|
| address | read/write | effect                            |
|=========|============|===================================|
| 0xfff0  | read       | if input is available, then read  |
|         |            | input into LSB, clearing MSB.     |
|         |            | if input is not available, then   |
|         |            | read -1                           |
|---------|------------|-----------------------------------|
| 0xfff1  | write      | write LSB to the terminal         |
|---------|------------|-----------------------------------|
| 0xfff2  | read/write | holds the memory access address   |
|---------|------------|-----------------------------------|
| 0xfff3  | read/write | holds the storage block index     |
|---------|------------|-----------------------------------|
| 0xfff4  | write      | write the given number of blocks  |
|         |            | from memory starting at the       |
|         |            | access address into storage       |
|         |            | starting at the block index       |
|---------|------------|-----------------------------------|
| 0xfff5  | write      | read the given number of blocks   |
|         |            | from storage starting at the      |
|         |            | block index into memory starting  |
|         |            | at the access address             |
|---------|------------|-----------------------------------|
| 0xfff6  | read       | read the number of attached       |
|         |            | storage devices                   |
|---------|------------|-----------------------------------|
| 0xfff7  | write      | set which storage device to       |
|         |            | access, 0-indexed                 |
|---------|------------|-----------------------------------|
| 0xfff8  | write      | set the given number of bytes     |
|         |            | starting at the memory access     |
|         |            | address to 0                      |
|---------|------------|-----------------------------------|
| 0xfff9  | read/write | holds the kernel boundary address |
|---------|------------|-----------------------------------|
| 0xfffa  | read/write | holds the kernel interrupt        |
|         |            | address. if code executing above  |
|         |            | the kernel boundary attempts to   |
|         |            | access MMIO or memory addresses   |
|         |            | less than or equal to the         |
|         |            | boundary, a jump to this address  |
|         |            | occurs                            |
|---------|------------|-----------------------------------|
| 0xfffb  | read       | holds the previous address an     |
|         |            | interrupt happened from           |
|---------|------------|-----------------------------------|
| 0xffff  | write      | halt execution                    |
|---------|------------|-----------------------------------|


Notes
-----
- addresses 0xfff0 and above are reserved for mmio and may not be executed
- attempting to read/write memory in and above the mmio range via storage access
  is a no-op
- attempting to read undefined storage will read 0
- block size is 1024 bytes
- at most 4 storage devices may be attached
- the kernel boundary address defaults to 0xffff
- all other read/write mmio addresses default to 0
- the previous interrupt address defaults to 0
- terminal i/o can use specific bytes to convey additional information

Terminal Input
--------------
|===============================|======|
| key                           | byte |
|===============================|======|
| enter                         | 0x0a |
|-------------------------------|------|
| backspace                     | 0x08 |
|-------------------------------|------|
| up arrow                      | 0xe9 |
|-------------------------------|------|
| down arrow                    | 0xea |
|-------------------------------|------|
| left arrow                    | 0xeb |
|-------------------------------|------|
| right arrow                   | 0xec |
|-------------------------------|------|
| insert                        | 0xee |
|-------------------------------|------|
| delete                        | 0xf8 |
|-------------------------------|------|
| home                          | 0xe8 |
|-------------------------------|------|
| end                           | 0xe5 |
|-------------------------------|------|

Terminal Output
--------------
|======|===============================|
| byte | purpose                       |
|======|===============================|
| 0x0a | move cursor down 1 row        |
|------|-------------------------------|
| 0x0d | move cursor all the way left  |
|------|-------------------------------|
| 0x08 | move cursor left 1 column     |
|------|-------------------------------|

Emulator
========

Usage
-----
  tundra <memory_file> [[-s storage_file] ...] [-d]

Notes
-----
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
  dw 0xFFFF


Tundra-Extra
------------
tundra-extra.inc includes tundra-core along with the following macros ('src'
marks a register that may be dereferenced, 'dest' marks one that may not be,
and 'imm' marks a 16-bit immediate. note that 'src' may not be '*pc' and
'dest' may not be 'pc'.) registers marked 'dest' may be modified by the macro:

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

  ; jump to src2 if dest and src1 are equal
  JEQ dest1, src1, src2

  ; jump to imm if dest and src are equal
  JEQI dest, src, imm

  ; jump to src2 if dest and src1 are not equal
  JNE dest, src1, src2

  ; jump to imm if dest and src are not equal
  JNERI, dest, src, imm

  ; jump to imm2 if dest and imm1 are not equal
  JNEI, dest, imm1, imm2

  ; jump to src2 if dest and src1 are equal, assert dest and src1 are positive
  JEQP dest, src1, src2

  ; jump to imm if dest and src are equal, assert dest and src are positive
  JEQPRI dest, src, imm

  ; jump to imm2 if dest and imm1 are equal, assert dest and imm1 are positive
  JEQPI dest, imm1, imm2

  ; set C to STACK_BASE
  ; this macro must be called before the first time a macro that uses the stack
  ; is called
  ; macros that use the stack reserve C as the stack pointer
  ; you may access the stack pointer with SP once initialized
  STACK_INIT

  ; push src to the stack
  PUSH src

  ; push imm to the stack
  PUSHI imm
  
  ; pop a word from the stack into dest
  POP dest

  ; pop a word of the stack into PC
  ; has no effect if CMP flag is set
  POPJ

  ; remove the top src bytes of the stack
  DROP src

  ; remove the top imm bytes of the stack
  DROPI imm

  ; copy a value that is src bytes deep in the stack to dest
  PEEK dest, src

  ; copy a value that is imm bytes deep in the stack to dest
  PEEKI dest, imm

  ; set a value that is src1 bytes deep in the stack to src2
  POKE src1, src2

  ; set a value that is src bytes deep in the stack to imm
  POKERI src, imm

  ; set a value that is imm bytes deep in the stack to src
  POKEIR imm, src

  ; set a value that is imm1 bytes deep in the stack to imm2
  POKEI imm1, imm2

  ; push the next address to the stack and jump to src
  ; has no effect if CMP flag is set
  CALL src
  
  ; push the next address to the stack and jump to imm
  ; has no effect if CMP flag is set
  CALLI src

  ; call imm if dest and src are equal
  CEQRI dest, src, imm

  ; call imm2 if dest and imm1 are not equal
  CNEI dest, imm1, imm2

  ; call imm if dest and src are not equal
  CNERI dest, src, imm

  ; call imm2 if dest and imm1 are equal
  CEQI dest, imm1, imm2

  ; call imm if dest and src are equal, assert dest and src are positive
  CEQPRI dest, src, imm

  ; call imm2 if dest and imm1 are equal, assert dest and src are positive
  CEQPI dest, imm1, imm2

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

  MMIO.READ_CHAR = 0xFFF0

  MMIO.WRITE_CHAR = 0xFFF1

  MMIO.ACCESS_ADDRESS = 0xFFF2

  MMIO.BLOCK_INDEX = 0xFFF3

  MMIO.WRITE_STORAGE = 0xFFF4

  MMIO.READ_STORAGE = 0xFFF5

  MMIO.STORAGE_COUNT = 0xFFF6

  MMIO.STORAGE_INDEX = 0xFFF7

  MMIO.ZERO_MEMORY = 0xFFF8

  MMIO.BOUNDARY_ADDRESS = 0xFFF9

  MMIO.INTERRUPT_ADDRESS = 0xFFFA

  MMIO.PREVIOUS_INTERRUPT = 0xFFFB

  MMIO.HALT = 0xFFFF

  STACK_BASE = 0xFFEE

  ; the following is only defined once STACK_INIT is run
  SP = C


License
=======

- the contents of this repository are licensed under the 3-Clause BSD license
  unless otherwise specified
- tundra-core.inc and tundra-extra.inc are licensed under the 0-Clause BSD
  license

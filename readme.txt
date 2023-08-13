==========
= Tundra =
==========


ISA
===

Format
------
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
*PC = 111 // auto-incremented by register-width after dereference


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

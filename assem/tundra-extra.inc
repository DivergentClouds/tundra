; various extra fasmg macros for Tundra

; Permission to use, copy, modify, and/or distribute this software for
; any purpose with or without fee is hereby granted.

; THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL
; WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
; OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
; FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY
; DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
; AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
; OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

include 'tundra-core.inc'

virtual at 0xfff0
	mmio:
	.input_available? = 0xfff0
	.read_char? = 0xfff1
	.write_char? = 0xfff2
	.seek_lsw? = 0xfff3
	.seek_msb? = 0xfff4
	.chunk_size? = 0xfff5
	.read_chunk? = 0xfff6
	.write_chunk? = 0xfff7
	.halt? = 0xffff
end virtual

stack_base = 0xFFEE

; jump
macro jmp? src
	mov pc, src
end macro

; jump immediate
macro jmpi? imm
	movi pc, imm
end macro

; jump if equal
macro jeq? dest1, dest2, src
	local next, skip

	cmp dest1, dest2
	jmpi next ; dest1 <= dest2

	jmpi skip ; dest1 > dest2

	next:
	cmp dest2, dest1
	jmp src ; dest2 <= dest1 -> dest1 == dest2

	skip:
end macro

; jump if equal immediate
macro jeqi? dest1, dest2, imm
	jeq dest1, dest2, *pc
	dw imm
end macro

; jump if not equal
macro jne? dest1, dest2, src
	local skip

	jeqi dest1, dest2, skip
	jmp src
	skip:
end macro

; jump if not equal immediate
macro jnei? dest1, dest2, imm
	jne dest1, dest2, *pc
	dw imm
end macro

; must be called before other stack macros
; reserves C for use as the stack pointer
macro stack_init?
	movi c, stack_base
end macro

macro push? src
	sto c, src
	addi c, -2
end macro

macro pushi? imm
	stoi c, imm
	addi c, -2
end macro

macro pop? dest
	addi c, 2
	mov dest, *c
end macro

macro drop?
	addi c, 2
end macro

macro call? src
	local ret_addr

	pushi ret_addr
	jmp src
	drop			; if cmp caused jump to be skipped, drop return address
	ret_addr:
end macro

macro calli? imm
	local ret_addr

	pushi ret_addr
	jmpi imm
	drop			; if cmp caused jump to be skipped, drop return address
	ret_addr:
end macro

macro ret?
	pop pc
end macro